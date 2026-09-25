// Orbital Dock — pinned + running apps for the bar's left slot.
//
// Adapted from claudsondouglas/arc.dock (MIT) — its app-grouping,
// pin/launch/focus, and FileView-persistence design is real, tested
// code; this file borrows that exact technique, trimmed down to what a
// bar-widget needs. Dropped on purpose (arc.dock has all of this, this
// widget doesn't): its own floating PanelWindow, magnification,
// notification badges, recents group, settings UI, and self-injected
// Hyprland blur rules (the bar's own translucency comes from a local
// Style.shellOpacity fallback instead — see the patch note in
// charlieras262.floating-bar's own Bar.qml).
//
// Real APIs used here (verified against arc.dock's own working code, the
// first-party AppLibrary.qml/Menu.qml, and Quickshell's own Util.qml —
// never invented; see git history for the appLibrary/iconSource dead
// end this replaced):
//   - Quickshell.Wayland's ToplevelManager.toplevels.values[i].appId:
//     the running window's app id, arc.dock's own real grouping key —
//     used here over Hyprland.toplevels specifically because it's the
//     same source arc.dock itself groups by.
//   - DesktopEntries.applications.values / .heuristicLookup(id): real
//     .desktop entries, each with .id/.icon/.name.
//   - Quickshell.iconPath(name, true): the base Quickshell icon-theme
//     lookup — global, not routed through the shell's own appLibrary
//     singleton (a bar-widget only gets PluginBarApi's restricted
//     facade, which doesn't forward `shell`/`appLibrary` to
//     third-party widgets — confirmed by reading Ui/PluginBarApi.qml).
//   - Util.execDetached("uwsm-app -- gtk-launch <id>.desktop"): the
//     exact command AppLibrary.launch() itself runs, reproduced
//     directly since that method lives on the inaccessible appLibrary.
//   - Hyprland.dispatch("focuswindow address:0x" + address): focuses
//     even a minimized window (Hyprland parks a minimized window
//     off-screen; the Wayland activate() protocol silently no-ops on
//     that — same reasoning arc.dock's own focusWindow() documents).
//   - FileView with atomicWrites for pinned-app persistence: same
//     pattern arc.dock's own state file uses, at a distinct path
//     (orbital-dock.json) so the two plugins never share — or race on
//     — the same file.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "orbital.dock"

  // --------------------------------------------------------- app identity

  function keyFor(appId) {
    var id = String(appId || "").trim().toLowerCase()
    if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
    return id
  }

  function entryFor(id) {
    var apps = (DesktopEntries.applications && DesktopEntries.applications.values) || []
    for (var i = 0; i < apps.length; i++) {
      var candidate = apps[i]
      if (candidate && String(candidate.id || "").toLowerCase() === id) return candidate
    }
    return (DesktopEntries.heuristicLookup && DesktopEntries.heuristicLookup(id)) || null
  }

  // Mirrors AppLibrary.iconSource()'s own precedence, including its
  // manual iconIndex (see below) — confirmed necessary, not cargo-culted:
  // Quickshell.iconPath("com.mitchellh.ghostty", true) and
  // ("files-native", true) both resolve empty on this machine even
  // though /usr/share/icons/hicolor/*/apps/{name}.png are real files and
  // the active theme (Yaru-blue) inherits hicolor as its last fallback —
  // Quickshell's own theme-chain walk doesn't find them, first-party
  // AppLibrary.iconSource() hits the exact same gap and works around it
  // the same way (a `find` over the XDG icon dirs, first match wins).
  function iconSourceFor(entry) {
    var value = String((entry && entry.icon) || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var indexed = root.iconIndex[value]
    if (indexed) return Util.fileUrl(indexed)
    var themed = Quickshell.iconPath(value, true)
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  // ------------------------------------------------------------ icon index

  // Same technique as the first-party AppLibrary.iconSource() (see
  // iconSourceFor above for why it's needed): scan every XDG icon dir by
  // filename instead of trusting Quickshell's theme-chain resolution.
  // SVGs listed before PNGs so the parser (first hit per name wins)
  // prefers scalable icons.
  property var iconIndex: ({})
  property var pendingIconIndex: ({})

  function iconIndexScanCommand() {
    return [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'for ext in svg png; do',
      '  for base in $dirs; do',
      '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
      'done'
    ].join(' ')
  }

  function indexIconLine(path) {
    var value = String(path || "").trim()
    if (value.length === 0) return
    var slash = value.lastIndexOf("/")
    var file = slash >= 0 ? value.slice(slash + 1) : value
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file
    if (name.length > 0 && root.pendingIconIndex[name] === undefined)
      root.pendingIconIndex[name] = value
  }

  Process {
    id: iconIndexScan
    command: ["bash", "-c", root.iconIndexScanCommand()]
    stdout: SplitParser { onRead: function(line) { root.indexIconLine(line) } }
    onStarted: root.pendingIconIndex = ({})
    // This scan takes a few seconds, so the dock's very first paint
    // resolves icons through Quickshell's own image://icon/ provider
    // (whatever it can find on its own — fine most of the time, but
    // exactly the path that silently misses com.mitchellh.ghostty and
    // files-native, see iconSourceFor's header comment). Reassigning
    // `pinned` to a new array once the scan lands forces `slots` to
    // recompute and the Repeater to recreate its delegates, so every
    // icon gets a second, authoritative resolution against the now-full
    // index instead of being stuck with its first guess.
    onExited: {
      root.iconIndex = root.pendingIconIndex
      root.pinned = root.pinned.slice()
    }
    Component.onCompleted: running = true
  }

  // --------------------------------------------------------------- running

  readonly property var runningToplevels: (ToplevelManager.toplevels && ToplevelManager.toplevels.values) || []

  function toplevelFor(id) {
    for (var i = 0; i < root.runningToplevels.length; i++) {
      var t = root.runningToplevels[i]
      if (t && root.keyFor(t.appId) === id) return t
    }
    return null
  }

  // ---------------------------------------------------------------- pinned

  // { key, entry } per pinned app — entry is the .desktop id, key is the
  // lowercased app id windows are grouped by (see keyFor). Seeded with
  // this machine's real, installed apps on first run only; after that
  // the file is the only source of truth (see loadState below).
  property var pinned: [
    { key: "google-chrome", entry: "google-chrome" },
    { key: "code", entry: "code" },
    { key: "com.mitchellh.ghostty", entry: "com.mitchellh.ghostty" },
    { key: "files-native", entry: "files-native" },
    { key: "obsidian", entry: "obsidian" },
    { key: "whatsapp", entry: "WhatsApp" },
    { key: "chatgpt", entry: "chatgpt" }
  ]

  function pinIndex(key) {
    for (var i = 0; i < root.pinned.length; i++) {
      if (root.pinned[i].key === key) return i
    }
    return -1
  }

  // ---------------------------------------------------------------- tooltip

  // A real Qt Quick Controls ToolTip (PanelToolTip) draws inside its
  // hovered item's own window — this bar is only `barSize` (~32px) tall,
  // so the tooltip has no room to actually float above the icon inside
  // that surface and ends up drawn overlapping it instead. PopupCard
  // (already used for the context menu below) is a separate popup
  // window, so it has the room a plain ToolTip doesn't; its own
  // `triggerMode: "hover"` mode is built for exactly this, no click/grab
  // involved.
  property var tooltipAnchorItem: null
  property string tooltipText: ""
  property real tooltipTargetX: 0

  function showTooltipFor(slot) {
    if (root.menuKey.length > 0) return
    var win = slot.QsWindow.window
    if (win) root.tooltipTargetX = slot.mapToItem(win.contentItem, slot.width / 2, 0).x
    root.tooltipAnchorItem = slot
    root.tooltipText = (slot.entry ? slot.entry.name : slot.key) + "  ·  right-click for options"
  }

  function hideTooltip() {
    root.tooltipAnchorItem = null
  }

  // ----------------------------------------------------------- context menu

  property var menuAnchorItem: null
  property string menuKey: ""
  property string menuEntryName: ""
  property bool menuIsPinned: false
  property bool menuHasEntry: true

  function openMenuFor(slot) {
    root.hideTooltip()
    root.menuAnchorItem = slot
    root.menuKey = slot.key
    root.menuEntryName = slot.entry ? slot.entry.name : slot.key
    root.menuIsPinned = slot.pinned
    // No real .desktop entry resolved (e.g. the app was uninstalled but
    // stayed pinned) — "Open" wouldn't do anything useful, so it's
    // hidden rather than offering a click that silently fails.
    root.menuHasEntry = slot.entry !== null && slot.entry !== undefined
  }

  function closeMenu() {
    root.menuKey = ""
    root.menuAnchorItem = null
  }

  function togglePin(key) {
    var at = root.pinIndex(key)
    var next = root.pinned.slice()
    if (at >= 0) {
      next.splice(at, 1)
    } else {
      var entry = root.entryFor(key)
      next.push({ key: key, entry: entry ? String(entry.id || key) : key })
    }
    root.pinned = next
    root.saveState()
  }

  function reorderPinned(fromIndex, toIndex) {
    if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0) return
    if (fromIndex >= root.pinned.length || toIndex >= root.pinned.length) return
    var next = root.pinned.slice()
    var moved = next.splice(fromIndex, 1)[0]
    next.splice(toIndex, 0, moved)
    root.pinned = next
    root.saveState()
  }

  // ----------------------------------------------------------- slot order

  // Pinned first (saved order), then whatever's running and not pinned,
  // in the order ToplevelManager reports it — no separate "recents"
  // group (arc.dock has one; this widget skips it, see file header).
  readonly property var slots: {
    var seen = ({})
    var list = []
    for (var p = 0; p < root.pinned.length; p++) {
      var pk = root.pinned[p].key
      if (seen[pk]) continue
      seen[pk] = true
      list.push({ key: pk, entry: root.entryFor(pk) || root.entryFor(root.pinned[p].entry), pinned: true })
    }
    for (var i = 0; i < root.runningToplevels.length; i++) {
      var top = root.runningToplevels[i]
      if (!top) continue
      var rk = root.keyFor(top.appId)
      if (rk.length === 0 || seen[rk]) continue
      seen[rk] = true
      list.push({ key: rk, entry: root.entryFor(rk), pinned: false })
    }
    return list
  }

  function focusOrLaunch(key) {
    var toplevel = root.toplevelFor(key)
    if (toplevel && toplevel.wayland === undefined) {
      // ToplevelManager's own toplevel *is* the address-bearing handle
      // under Hyprland (no separate .wayland indirection needed here,
      // unlike going through Hyprland.toplevels) — but address still
      // only exists when Hyprland itself is the compositor, so fall
      // through to activate() when it doesn't.
    }
    var hyprMatch = null
    var hyprList = (Hyprland.toplevels && Hyprland.toplevels.values) || []
    for (var i = 0; i < hyprList.length; i++) {
      var h = hyprList[i]
      if (h && h.wayland === toplevel) { hyprMatch = h; break }
    }
    if (hyprMatch && hyprMatch.address) {
      var target = "address:0x" + hyprMatch.address
      Hyprland.dispatch(Hyprland.usingLua
        ? 'hl.dsp.focus({ window = "' + target + '" })'
        : "focuswindow " + target)
      return
    }
    if (toplevel && typeof toplevel.activate === "function") {
      toplevel.activate()
      return
    }
    // Same command AppLibrary.launch() runs — see the file header.
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(key + ".desktop"))
  }

  // -------------------------------------------------------- persistence

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/omarchy"
  readonly property string statePath: root.stateDir + "/orbital-dock.json"
  property bool stateAnswered: false

  function loadState(raw) {
    var text = String(raw || "").trim()
    if (text.length === 0) return
    var data = null
    try {
      data = JSON.parse(text)
    } catch (error) {
      console.warn("orbital.dock: could not read state from", root.statePath, "-", error)
      return
    }
    var list = (data && data.pinned && data.pinned.length !== undefined) ? data.pinned : []
    var out = []
    var seen = ({})
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      var key = String(item.key || "").trim().toLowerCase()
      if (key.length === 0 || seen[key]) continue
      seen[key] = true
      out.push({ key: key, entry: String(item.entry || key) })
    }
    if (out.length > 0) root.pinned = out
  }

  function saveState() {
    if (!root.stateAnswered) return
    stateFile.setText(JSON.stringify({ version: 1, pinned: root.pinned }, null, 2) + "\n")
  }

  FileView {
    id: stateFile
    path: root.statePath
    // Watched so the launcher's "Pin to Dock" (which writes this file) shows up
    // live; reload only re-reads state, it never writes, so no feedback loop.
    watchChanges: true
    onFileChanged: reload()
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.loadState(text())
      root.stateAnswered = true
    }
    onLoadFailed: root.stateAnswered = true
    onSaveFailed: function(error) {
      console.warn("orbital.dock: could not write state to", root.statePath, "-", error)
    }
    Component.onCompleted: reload()
  }

  // A single reusable row type for the context menu's two entries.
  component MenuRow: Rectangle {
    id: menuRow
    required property string label
    signal activated()

    width: parent ? parent.width : 0
    height: Style.space(30)
    radius: Style.space(8)
    color: menuRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: menuRow.label
      color: root.bar ? root.bar.foreground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
    }

    MouseArea {
      id: menuRowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: menuRow.activated()
    }
  }

  // -------------------------------------------------------------- layout

  implicitWidth: row.implicitWidth + Style.space(4)
  implicitHeight: root.barSize

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    // Avatar — left click opens orbital.account (the mockup's profile
    // panel: real name/email, Appearance/Keyboard Shortcuts links,
    // Lock/Sleep/Restart/Shut Down — see Account.qml's own header for
    // what's real vs. left out). Right click opens a terminal. A real
    // photo when one is set (~/.config/omarchy/avatar.png); falls back
    // to the Omarchy icon ($OMARCHY_PATH/icon.png) when it isn't.
    Item {
      id: avatarSlot
      width: root.barSize
      height: root.barSize

      // Util.fileUrl (not a hand-rolled "file://" + path concat) is the
      // same helper AppLibrary.iconSource() itself uses for an absolute
      // icon path — see iconSourceFor() above. Falls back to a real,
      // themed "avatar-default" icon (Quickshell.iconPath, the same
      // proven mechanism every app icon in this dock already uses) —
      // not a custom glyph font, which rendered fully blank here for a
      // reason not yet root-caused; this sidesteps it rather than
      // shipping a dock avatar that's invisible half the time.
      readonly property string avatarSource: {
        var path = Quickshell.env("HOME") + "/.config/omarchy/avatar.png"
        return Util.fileUrl(path)
      }

      // Only try the picture when the file exists (a missing one logs a warning per load).
      FileView {
        id: avatarFile
        path: Quickshell.env("HOME") + "/.config/omarchy/avatar.png"
        printErrors: false
        watchChanges: false
      }

      // Circular masking (layer.effect + MultiEffect) rendered this
      // whole Item blank in practice, root cause not yet nailed down —
      // dropped rather than shipping an invisible avatar. Square for
      // now; worth another pass later.
      Image {
        id: avatarImage
        anchors.centerIn: parent
        width: parent.width * 0.72
        height: width
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        source: avatarFile.loaded ? avatarSlot.avatarSource : ""
        cache: false
        visible: status === Image.Ready
      }

      Image {
        anchors.centerIn: parent
        width: parent.width * 0.72
        height: width
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        visible: avatarImage.status !== Image.Ready
        source: Util.fileUrl((Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/icon.png")
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          if (!root.bar) return
          if (mouse.button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
          else root.bar.run("omarchy-shell shell toggle orbital.account '{}'")
        }
      }
    }

    // Divider — pinned/running apps read as their own group, distinct
    // from the avatar/menu button before them (same idea as arc.dock's
    // own `showSeparator`, simplified to a fixed hairline).
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 1
      height: root.barSize * 0.5
      color: root.bar ? root.bar.foreground : Color.foreground
      opacity: 0.18
    }

    Item { width: Style.space(2); height: 1 }

    Repeater {
      id: repeater
      model: root.slots

      Item {
        id: slot
        required property int index
        required property var modelData

        readonly property string key: modelData.key
        readonly property var entry: modelData.entry
        readonly property bool pinned: modelData.pinned === true
        readonly property var toplevel: root.toplevelFor(key)
        readonly property bool running: toplevel !== null
        readonly property bool focused: running && toplevel === ToplevelManager.activeToplevel

        width: root.barSize
        height: root.barSize
        z: dragArea.drag.active ? 10 : 0

        Drag.active: slot.pinned && dragArea.drag.active
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        Image {
          anchors.centerIn: parent
          width: parent.width * 0.62
          height: width
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          source: root.iconSourceFor(slot.entry)
          opacity: dragArea.drag.active ? 0.5 : 1
        }

        // Open, not focused: a small accent dot. Pinned-but-closed gets
        // no mark at all — the mark means "running", not "pinned", so a
        // closed pinned app reads the same as an unpinned one until it's
        // actually launched.
        Rectangle {
          visible: slot.running && !slot.focused
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottomMargin: 2
          width: Style.space(3)
          height: Style.space(3)
          radius: width / 2
          color: Color.accent
        }

        // Open AND focused: the dot becomes a short underline instead —
        // same accent color, just a different shape so "running" and
        // "this is the window you're looking at right now" don't read
        // as the same mark.
        Rectangle {
          visible: slot.focused
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottomMargin: 2
          width: parent.width * 0.5
          height: Style.space(2)
          radius: height / 2
          color: Color.accent
        }

        MouseArea {
          id: dragArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          drag.target: slot.pinned ? slot : undefined
          drag.axis: Drag.XAxis
          // Set true only when a real drag actually starts (pinned slots
          // only, per drag.target above) — not on every press. A plain
          // click, left or right, never flips this.
          property bool wasDragged: false

          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) root.openMenuFor(slot)
            else root.focusOrLaunch(slot.key)
          }
          // Snap the drag offset back to 0 once a real drag ends — Row
          // takes over positioning again on the next relayout (the actual
          // reorder already happened live via DropArea below). Gating on
          // wasDragged, not slot.pinned, matters: the previous version
          // reset x/y on every release regardless of whether a drag ever
          // happened, which stomped the Row-computed x of whichever
          // pinned slot was simply clicked back to 0 for a frame —
          // harmless visually (the Row's own layout wins back on the next
          // relayout) but caught live: it fed a stale x=0 into the
          // right-click menu's position lookup at the exact moment the
          // click fired, which is why the menu kept landing at the
          // dock's start instead of under the actual icon.
          onReleased: {
            if (!dragArea.wasDragged) return
            dragArea.wasDragged = false
            slot.x = 0
            slot.y = 0
          }
          drag.onActiveChanged: if (drag.active) dragArea.wasDragged = true
          onEntered: root.showTooltipFor(slot)
          onExited: if (root.tooltipAnchorItem === slot) root.hideTooltip()
        }

        DropArea {
          anchors.fill: parent
          onEntered: function(drag) {
            if (!slot.pinned) return
            var source = drag.source
            if (!source || source === slot || !source.pinned) return
            root.reorderPinned(source.index, slot.index)
          }
        }
      }
    }
  }

  // Hover tooltip — a passive overlay PanelWindow (no keyboard focus,
  // empty input mask so the pointer passes straight through), not
  // PopupCard: same xdg-popup stacking bug as the old context menu — real
  // windows rendered on top of it, leaving the tip clipped at the bottom.
  // X comes from the same bar-window mapToItem KeyboardPanel uses for its
  // own anchoring (tooltipTargetX, captured in showTooltipFor).
  PanelWindow {
    id: tooltip
    visible: root.tooltipAnchorItem !== null
    anchors { left: true; bottom: true }
    margins {
      left: Math.max(Style.space(8), Math.round(root.tooltipTargetX - implicitWidth / 2))
      bottom: root.barSize + Style.space(16)
    }
    implicitWidth: tooltipText.implicitWidth + Style.space(16)
    implicitHeight: tooltipText.implicitHeight + Style.space(8)
    color: "transparent"
    mask: Region {}
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "orbital-dock-tooltip"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Color.popups.background
      border.width: 1
      border.color: Color.popups.border
      radius: Style.cornerRadius
    }

    Text {
      id: tooltipText
      anchors.centerIn: parent
      text: root.tooltipText
      color: root.bar ? root.bar.foreground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }

  // Right-click context menu — KeyboardPanel (Ui/KeyboardPanel.qml), the
  // same base orbital.clock's calendar popup uses, not PopupCard
  // (Ui/PopupCard.qml). PopupCard builds an xdg-popup anchored to the
  // bar's own layer-shell surface, and on this system that popup does
  // NOT inherit the bar's own above-everything stacking: a real window
  // (confirmed with a normal terminal) rendered ON TOP of it, leaving
  // only a sliver of the menu poking out in the gap between the window's
  // bottom edge and the bar — reproduced and screenshotted live, not a
  // guess. KeyboardPanel's WlrLayer.Overlay always renders above real
  // windows, and — unlike a hand-rolled full-screen PanelWindow — its
  // `anchorScreenPos`/`cardOrigin` math is already the tested, working
  // way this project positions a popup under a bar-hosted item (see
  // orbital.clock/Panel.qml, fixed and confirmed correct earlier this
  // session): a naive `mapToItem` chained across windows here first put
  // the menu nowhere near the clicked icon, which KeyboardPanel's own
  // known-bar-geometry approach avoids. Its dynamic Exclusive→OnDemand
  // keyboard-focus toggle was the thing this file originally avoided
  // (the "clock-freeze" risk) — that risk is what the comment called
  // "since-patched", confirmed itself this session: the calendar popup
  // above uses this exact same component, through several full shell
  // restarts, with no freeze.
  KeyboardPanel {
    id: contextMenu
    anchorItem: root.menuAnchorItem
    owner: ({ close: root.closeMenu })
    bar: root.bar
    open: root.menuKey.length > 0
    centerOnBar: false
    focusTarget: menuKeyCatcher
    contentWidth: contextMenu.fittedContentWidth(Style.space(180))
    contentHeight: contextMenu.fittedContentHeight(menuColumn.implicitHeight)

    Item {
      id: menuKeyCatcher
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.closeMenu(); event.accepted = true }
      }

      Column {
        id: menuColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        MenuRow {
          label: "Open"
          visible: root.menuHasEntry
          height: visible ? implicitHeight : 0
          onActivated: {
            root.focusOrLaunch(root.menuKey)
            root.closeMenu()
          }
        }

        MenuRow {
          label: root.menuIsPinned ? "Remove from Dock" : "Pin to Dock"
          onActivated: {
            root.togglePin(root.menuKey)
            root.closeMenu()
          }
        }
      }
    }
  }
}
