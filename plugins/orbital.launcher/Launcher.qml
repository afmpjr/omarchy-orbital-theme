// Orbital Launcher — the mockup's centered app drawer: search bar with a
// shortcut hint, category pills, a 6-column grid of real installed apps.
//
// Structurally adapted from younesdahdouh/omarchy-super-apps (MIT) — its
// open/close/toggle(shell-summon contract), keyboard-driven search (no
// real TextInput; a focused Item's Keys.onPressed edits filterText via
// Util.editsFilter/editedFilter, exactly like the first-party Emojis
// overlay does), and arrow/page-key grid navigation are real, working
// code, kept close to the original. Restyled to match this session's
// mockup (search icon + shortcut badge, category pills, fixed 6-col
// grid) and extended with category filtering (real DesktopEntry.categories,
// confirmed via quickshell-core.qmltypes — not guessed) and a wheel
// gesture on the pill row.
//
// `shell` is injected automatically for any panel/overlay/menu-kind
// plugin (confirmed by reading shell.qml's own Loader.onLoaded —
// `if ("shell" in item) item.shell = ...`), unlike a bar-widget, which
// only gets PluginBarApi's restricted facade (see orbital.dock's own
// Dock.qml header for that distinction). `shell.appLibrary` specifically
// stayed null here in every configuration tried (kinds with/without
// "menu", with/without keepLoaded, across many full shell restarts) —
// and checking a real, well-regarded community launcher confirms this
// isn't a config mistake to keep chasing: maajix/omarchy-spotlight
// (kinds: ["overlay","menu"], keepLoaded: true — the same shape tried
// here) treats appLibrary as best-effort throughout its own code
// (`if (root.appLibrary) ... else <direct DesktopEntries fallback>`,
// see its lib/Apps.js and Spotlight.qml's appIcon()/launchApp()). So
// this file does the same, unconditionally, rather than depending on a
// plugin-host behavior that isn't reliable for a third-party overlay in
// this Omarchy version: every app-facing function below resolves
// through DesktopEntries directly (AppSearch.js, ported verbatim from
// the first-party file of the same name, for identical fuzzy-search/
// sort behavior) and only takes a shortcut through appLibrary when it
// happens to be present. iconSourceFor/launchApp/removeApp mirror
// orbital.dock's own already-verified DesktopEntries-direct approach
// (including its manual iconIndex scan — Quickshell.iconPath() alone
// misses com.mitchellh.ghostty/files-native on this machine, see
// Dock.qml's header for the full diagnosis) and omarchy-spotlight's own
// fallback for the same gap, independently arriving at the same fix.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "AppSearch.js" as AppSearch
import "../orbital.ui" as OrbitalUi

Item {
  id: root

  function tr(s) { return OrbitalUi.OrbitalI18n.t(s) }
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var deleteTarget: null
  property bool deleteConfirmOpen: false

  readonly property var categoryDefs: [
    { id: "all", label: tr("All Apps"), match: [] },
    { id: "productivity", label: tr("Productivity"), match: ["Office", "Network"] },
    { id: "development", label: tr("Development"), match: ["Development"] },
    { id: "media", label: tr("Media"), match: ["AudioVideo", "Graphics", "Video"] },
    { id: "utilities", label: tr("Utilities"), match: ["Utility", "System", "Settings"] },
    { id: "games", label: tr("Games"), match: ["Game"] }
  ]
  property string activeCategory: "all"

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(1)))
  property color scrim: "transparent"
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Math.max(0, Style.cornerRadius - 2)
  readonly property int cardRadius: Style.cornerRadius
  property string fontFamily: Style.font.family
  property int contentMargin: Style.spacing.panelPadding
  property int searchHeight: Style.space(42)
  property int pillsHeight: Style.space(36)
  // Layout slot the pill row occupies: shorter than the pills themselves so
  // the grid starts ~10px closer (measured 1:1 against the mockup).
  readonly property int pillsSlot: pillsHeight - Style.space(12)
  // Mockup gap between blocks (search / tabs / grid): ~22px rendered.
  property int contentSpacing: Style.space(26)
  property int cardWidth: Math.min(Style.space(594), panel.width - Style.gapsOut * 4)
  // Three grid rows + the Recommended block (header + 3 rows of 2), the
  // mockup's full drawer. When the block is hidden (typing a search, or a
  // category other than All) the grid simply takes that space back.
  property int recRowHeight: Style.space(56)
  property bool recExpanded: false
  readonly property int recLimit: recExpanded ? 12 : 6
  readonly property int recRows: Math.max(1, Math.ceil(recModel.count / 2))
  property int recHeaderHeight: Style.space(42)
  property int recBlockHeight: recHeaderHeight + recRowHeight * recRows + Style.space(2)
  readonly property bool recVisible: filterText.length === 0 && activeCategory === "all" && recModel.count > 0
  property int cardHeight: Math.min(contentMargin * 2 + searchHeight + pillsSlot + contentSpacing * 3 + cellHeight * 3 + recBlockHeight, panel.height - Style.gapsOut * 4)

  property int columns: 6
  property int cellHeight: Style.space(92)
  property int iconSize: Style.space(42)

  // Category the app is shown under when it has no manual override: the first
  // tab whose accepted .desktop categories it declares ("" = only All Apps).
  function autoCategoryOf(entry) {
    for (var i = 1; i < root.categoryDefs.length; i++)
      if (root.matchesDef(entry, root.categoryDefs[i])) return root.categoryDefs[i].id
    return ""
  }

  function matchesDef(entry, def) {
    var cats = (entry && entry.categories) || []
    for (var c = 0; c < cats.length; c++)
      if (def.match.indexOf(String(cats[c])) !== -1) return true
    return false
  }

  function categoryMatches(entry, categoryId) {
    if (categoryId === "all") return true
    var ov = entry ? root.categoryOverrides[String(entry.id || "")] : undefined
    if (ov !== undefined) return ov === categoryId
    var def = null
    for (var i = 0; i < root.categoryDefs.length; i++)
      if (root.categoryDefs[i].id === categoryId) { def = root.categoryDefs[i]; break }
    if (!def) return true
    var cats = (entry && entry.categories) || []
    for (var c = 0; c < cats.length; c++)
      if (def.match.indexOf(String(cats[c])) !== -1) return true
    return false
  }

  function sanitizeLabel(value) {
    var s = String(value || "").replace(/[\x00-\x1f\x7f]/g, " ").trim()
    var maxLength = 60
    if (s.length > maxLength) s = s.slice(0, maxLength) + "…"
    return s
  }

  // ------------------------------------------------------------ icon index
  // Identical technique to orbital.dock's Dock.qml (see its header for the
  // full diagnosis): Quickshell.iconPath() alone misses some real,
  // installed icons (confirmed for com.mitchellh.ghostty and files-native
  // on this machine) even with appLibrary unavailable to fall back on, so
  // this plugin runs the same manual XDG icon-dir scan first-party
  // AppLibrary.iconSource() itself relies on.
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
    onExited: {
      root.iconIndex = root.pendingIconIndex
      root.rebuildDisplay()
    }
    Component.onCompleted: running = true
  }

  function iconSourceFor(icon) {
    if (root.appLibrary) return root.appLibrary.iconSource(icon)
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var indexed = root.iconIndex[value]
    if (indexed) return Util.fileUrl(indexed)
    var themed = Quickshell.iconPath(value, true)
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  // ---- Recommended: real data only. Launch history is recorded here (per
  // app id: count + last launch time) in orbital-launcher.json; anything the
  // history can't fill comes from the newest .desktop files on disk
  // ("Recently added"). Nothing is invented — with no history and no
  // desktop files the whole section stays hidden.
  property var usage: ({})
  // Manual "Move to category" choices: appId -> category id. Absent = automatic.
  property var categoryOverrides: ({})
  property var recentlyAdded: []
  readonly property string usagePath: Quickshell.env("HOME") + "/.local/state/omarchy/orbital-launcher.json"

  ListModel { id: recModel }

  function recordUsage(appId) {
    var next = {}
    for (var k in root.usage) next[k] = root.usage[k]
    var cur = next[appId] || { count: 0, last: 0 }
    next[appId] = { count: (cur.count || 0) + 1, last: Date.now() }
    root.usage = next
    root.saveStore()
  }

  function saveStore() {
    usageFile.setText(JSON.stringify({ version: 1, usage: root.usage, categoryOverrides: root.categoryOverrides }, null, 2) + "\n")
  }

  FileView {
    id: usageFile
    path: root.usagePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var d = JSON.parse(text())
        root.usage = (d && d.usage) || ({})
        root.categoryOverrides = (d && d.categoryOverrides) || ({})
      } catch (e) { root.usage = ({}) }
      root.rebuildRecommended()
    }
    Component.onCompleted: reload()
  }

  Process {
    id: recentlyAddedProc
    command: ["bash", "-c", "find /usr/share/applications \"$HOME/.local/share/applications\" -maxdepth 1 -name '*.desktop' -printf '%T@ %f\\n' 2>/dev/null | sort -rn | head -30 | cut -d' ' -f2-"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.recentlyAdded = text.split("\n").filter(function(l) { return l.length > 0 }).map(function(l) { return l.replace(/\.desktop$/, "") })
        root.rebuildRecommended()
      }
    }
  }

  function entryById(id) {
    var values = (DesktopEntries.applications && DesktopEntries.applications.values) || []
    for (var i = 0; i < values.length; i++)
      if (String(values[i].id || "") === id) return values[i]
    return null
  }

  function rebuildRecommended() {
    recModel.clear()
    var seen = {}
    var out = []
    function push(id, why) {
      if (out.length >= root.recLimit || seen[id]) return
      var e = root.entryById(id)
      if (!e || e.noDisplay) return
      seen[id] = true
      out.push({ appId: id, label: root.sanitizeLabel(AppSearch.entryName(e)), appIcon: String(e.icon || ""), why: why })
    }
    var ids = Object.keys(root.usage)
    var byRecent = ids.slice().sort(function(a, b) { return root.usage[b].last - root.usage[a].last })
    var byCount = ids.slice().sort(function(a, b) { return root.usage[b].count - root.usage[a].count })
    for (var i = 0; i < byRecent.length && i < 2; i++) push(byRecent[i], tr("Recently used"))
    for (var j = 0; j < byCount.length && out.length < 4; j++) if (root.usage[byCount[j]].count >= 2) push(byCount[j], tr("Frequently used"))
    for (var m = 0; m < root.recentlyAdded.length; m++) push(root.recentlyAdded[m], tr("Recently added"))
    for (var n = 0; n < out.length; n++) recModel.append(out[n])
  }

  // ---- Per-app context menu (right-click). Every row is real: the app's
  // own .desktop Actions (New Window, Incognito, ...), Pin/Unpin against the
  // dock's persisted state file, and the existing confirmed Uninstall flow.
  property var appMenu: null          // { appId, label, x, y } while open
  property var appMenuItems: []       // [{ kind, label, action?, danger? }]
  property var dockPinned: []         // [{ key, entry }] mirror of orbital-dock.json
  readonly property string dockStatePath: Quickshell.env("HOME") + "/.local/state/omarchy/orbital-dock.json"

  FileView {
    id: dockFile
    path: root.dockStatePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try { var d = JSON.parse(text()); root.dockPinned = (d && d.pinned && d.pinned.length !== undefined) ? d.pinned : [] }
      catch (e) { root.dockPinned = [] }
    }
    onLoadFailed: root.dockPinned = []
    Component.onCompleted: reload()
  }

  function dockKeyFor(appId) {
    var id = String(appId || "").trim().toLowerCase()
    return id.slice(-8) === ".desktop" ? id.slice(0, -8) : id
  }

  function isPinned(appId) {
    var key = root.dockKeyFor(appId)
    for (var i = 0; i < root.dockPinned.length; i++)
      if (String((root.dockPinned[i] || {}).key || "").toLowerCase() === key) return true
    return false
  }

  function toggleDockPin(appId) {
    var key = root.dockKeyFor(appId)
    var list = root.dockPinned.slice()
    var at = -1
    for (var i = 0; i < list.length; i++)
      if (String((list[i] || {}).key || "").toLowerCase() === key) { at = i; break }
    if (at >= 0) list.splice(at, 1)
    else list.push({ key: key, entry: appId })
    root.dockPinned = list
    dockFile.setText(JSON.stringify({ version: 1, pinned: list }, null, 2) + "\n")
  }

  function openAppMenu(appId, label, item, mouse) {
    var entry = root.entryById(appId)
    var items = [{ kind: "open", label: tr("Open") }]
    var acts = (entry && entry.actions) || []
    for (var i = 0; i < acts.length; i++) {
      if (acts[i] && acts[i].name) items.push({ kind: "action", label: String(acts[i].name), action: acts[i] })
    }
    items.push({ kind: "pin", label: root.isPinned(appId) ? tr("Remove from Dock") : tr("Pin to Dock") })
    items.push({ kind: "movecat", label: tr("Move to category \u203A") })
    items.push({ kind: "more", label: tr("More options \u203A") })
    items.push({ kind: "uninstall", label: tr("Uninstall\u2026"), danger: true })
    var pos = item.mapToItem(cardContent, mouse.x, mouse.y)
    root.appMenuItems = items
    root.appMenu = { appId: appId, label: label, x: pos.x, y: pos.y }
  }

  function closeAppMenu() {
    root.appMenu = null
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Sub-menu content: swapped in place (same card/position) with a Back row.
  property var appMenuRootItems: []

  function launchCommandFor(appId) {
    var e = root.entryById(appId)
    if (!e) return ""
    var raw = String(e.execString || "")
    if (raw.length === 0 && e.command && e.command.length !== undefined) raw = Array.prototype.join.call(e.command, " ")
    // Drop .desktop field codes (%U, %f, ...): meaningless outside the launcher.
    return raw.replace(/\s*%[fFuUdDnNickvm]/g, "").trim()
  }

  function copyToClipboard(text, what) {
    if (!text) return
    Util.execDetached("bash -c " + Util.shellQuote('printf %s "$1" | wl-copy && notify-send -t 2500 "Copied" "$2"') + " _ " + Util.shellQuote(text) + " " + Util.shellQuote(what))
  }

  // Opens the folder that holds the app's .desktop file in the default file
  // manager (user dir first, then the XDG data dirs).
  function showDesktopFile(appId) {
    Util.execDetached("bash -c " + Util.shellQuote('id="$1"; IFS=:; for d in "$HOME/.local/share" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do f="$d/applications/$id.desktop"; [ -f "$f" ] && exec xdg-open "$(dirname "$f")"; done; notify-send -t 2500 "Not found" "$id.desktop"') + " _ " + Util.shellQuote(appId))
  }

  function runAppMenuItem(it) {
    var m = root.appMenu
    if (!m) return
    if (it.kind === "more") {
      root.appMenuRootItems = root.appMenuItems
      root.appMenuItems = [
        { kind: "back", label: tr("\u2039 Back") },
        { kind: "showfile", label: tr("Show in file manager") },
        { kind: "copycmd", label: tr("Copy launch command") },
        { kind: "copyid", label: tr("Copy app ID") }
      ]
      return
    }
    if (it.kind === "movecat") {
      root.appMenuRootItems = root.appMenuItems
      var entry = root.entryById(m.appId)
      var ov = root.categoryOverrides[m.appId]
      var cur = ov !== undefined ? ov : root.autoCategoryOf(entry)
      var list = [{ kind: "back", label: tr("\u2039 Back") }]
      for (var i = 1; i < root.categoryDefs.length; i++) {
        var d = root.categoryDefs[i]
        list.push({ kind: "setcat", catId: d.id, label: d.label, checked: cur === d.id })
      }
      list.push({ kind: "setcat", catId: "", label: tr("Automatic"), checked: ov === undefined })
      root.appMenuItems = list
      return
    }
    if (it.kind === "back") { root.appMenuItems = root.appMenuRootItems; return }
    if (it.kind === "setcat") {
      var next = {}
      for (var k in root.categoryOverrides) next[k] = root.categoryOverrides[k]
      if (it.catId === "") delete next[m.appId]
      else next[m.appId] = it.catId
      root.categoryOverrides = next
      root.saveStore()
      root.appMenu = null
      root.rebuildDisplay()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      return
    }
    root.appMenu = null
    if (it.kind === "open") root.launch(m.appId, m.label)
    else if (it.kind === "action") { root.close(); try { it.action.execute() } catch (e) { console.warn("orbital.launcher: action failed", e) } }
    else if (it.kind === "pin") { root.toggleDockPin(m.appId); Qt.callLater(function() { keyCatcher.forceActiveFocus() }) }
    else if (it.kind === "uninstall") { root.deleteTarget = { appId: m.appId, label: m.label }; root.deleteConfirmOpen = true }
    else if (it.kind === "showfile") { root.showDesktopFile(m.appId); root.close() }
    else if (it.kind === "copycmd") { root.copyToClipboard(root.launchCommandFor(m.appId), "Launch command for " + m.label); root.close() }
    else if (it.kind === "copyid") { root.copyToClipboard(m.appId, "App ID: " + m.appId); root.close() }
  }

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = false
    root.activeCategory = "all"
    root.recExpanded = false
    root.appMenu = null
    dockFile.reload()
    if (root.appLibrary && typeof root.appLibrary.refreshIcons === "function") root.appLibrary.refreshIcons()
    root.rebuildDisplay()
    recentlyAddedProc.running = false
    recentlyAddedProc.running = true
    usageFile.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle(payloadJson) {
    if (root.opened) root.close()
    else root.open(payloadJson)
  }

  function rebuildDisplay() {
    displayModel.clear()
    var rows
    if (root.appLibrary) {
      rows = root.appLibrary.sortedEntries(root.filterText)
    } else {
      var values = (DesktopEntries.applications && DesktopEntries.applications.values) || []
      rows = AppSearch.sortedEntries(values, root.filterText, null)
    }
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      if (!root.categoryMatches(entry, root.activeCategory)) continue
      displayModel.append({
        appId: appId,
        label: root.sanitizeLabel(root.appLibrary ? root.appLibrary.entryName(entry) : AppSearch.entryName(entry)),
        appIcon: String(entry.icon || "")
      })
    }
    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0
    Qt.callLater(function() {
      if (displayModel.count > 0) appGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
    })
  }

  function setCategory(categoryId) {
    root.activeCategory = categoryId
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  function cycleCategory(delta) {
    var idx = 0
    for (var i = 0; i < root.categoryDefs.length; i++)
      if (root.categoryDefs[i].id === root.activeCategory) { idx = i; break }
    idx = (idx + delta + root.categoryDefs.length) % root.categoryDefs.length
    root.setCategory(root.categoryDefs[idx].id)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = nextFilter.length > 0
    root.rebuildDisplay()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    appGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function selectRow(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
      appGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
      return
    }
    var newIndex = selectedIndex + delta * root.columns
    if (newIndex < 0) newIndex = 0
    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1
    selectedIndex = newIndex
    appGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function selectPage(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
      appGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
      return
    }
    var visibleRows = Math.max(1, Math.floor(appGrid.height / root.cellHeight))
    var newIndex = selectedIndex + delta * root.columns * visibleRows
    if (newIndex < 0) newIndex = 0
    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1
    selectedIndex = newIndex
    appGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.launch(row.appId, row.label)
  }

  function launch(appId, label) {
    if (!appId) return
    root.recordUsage(appId)
    root.close()
    if (root.appLibrary) { root.appLibrary.launch(appId, label); return }
    // Same command AppLibrary.launch() itself runs — see orbital.dock's
    // own focusOrLaunch() header for the identical reasoning.
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(appId + ".desktop"))
  }

  // Same flow as the Omarchy menu's own Apps submenu, and
  // younesdahdouh/omarchy-super-apps' own requestDeleteSelected(): Delete
  // asks for confirmation, then genuinely uninstalls the package (not
  // just hides the launcher entry) via omarchy-remove-launcher-entry,
  // which requires sudo — real, first-party AppLibrary.remove() runs the
  // exact same script, reproduced directly here for the no-appLibrary
  // fallback path.
  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    root.deleteTarget = { appId: row.appId, label: row.label }
    root.deleteConfirmOpen = true
  }

  // Own confirm dialog (the first-party ConfirmDialog draws a thick accent
  // border and square buttons that don't match the other Orbital cards).
  // Focus starts on Cancel: an Enter by reflex must never uninstall.
  property int deleteFocus: 0          // 0 = Cancel, 1 = Uninstall
  onDeleteConfirmOpenChanged: if (deleteConfirmOpen) deleteFocus = 0

  function handleDeleteKey(event) {
    if (event.key === Qt.Key_Escape) root.cancelDelete()
    else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
      root.deleteFocus = 1 - root.deleteFocus
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      if (root.deleteFocus === 1) root.confirmDelete()
      else root.cancelDelete()
    }
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target || !target.appId) return
    if (root.appLibrary) { root.appLibrary.remove(target.appId, target.label); return }
    if (!root.omarchyPath) return
    Util.execDetached(Util.shellQuote(root.omarchyPath + "/bin/omarchy-remove-launcher-entry")
      + " " + Util.shellQuote(target.appId) + " " + Util.shellQuote(target.label || target.appId))
  }

  function escapeMarkup(value) {
    return String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  ListModel { id: displayModel }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { if (root.opened) root.rebuildDisplay() }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "orbital-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cardRadius
      anchors.centerIn: parent
      anchors.verticalCenterOffset: Style.space(4)
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: cardContent
        anchors.fill: parent
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.deleteConfirmOpen) {
            root.handleDeleteKey(event)
            event.accepted = true
            return
          }
          if (root.appMenu) {
            if (event.key === Qt.Key_Escape) {
              if (root.appMenuItems.length > 0 && root.appMenuItems[0].kind === "back") root.runAppMenuItem(root.appMenuItems[0])
              else root.closeAppMenu()
            }
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            root.requestDeleteSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.cycleCategory(event.modifiers & Qt.ShiftModifier ? -1 : 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab) {
            root.cycleCategory(-1)
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selectRow(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.selectRow(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.selectPage(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.selectPage(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // Search bar — magnifying glass, live filter text (or placeholder),
        // a shortcut-hint badge on the right (mirrors the mockup's ⌘K
        // pill, spelled for this platform's real bind — see bindings.lua).
        Rectangle {
          width: parent.width
          height: root.searchHeight
          radius: root.cornerRadius
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.07)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

          Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - parent.radius * 2
            height: 1
            color: Color.accent
            opacity: 0.55
          }

          Image {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18)
            height: Style.space(18)
            fillMode: Image.PreserveAspectFit
            opacity: 0.85
            source: Quickshell.iconPath("edit-find", true)
          }

          Text {
            anchors.left: searchIcon.right
            anchors.leftMargin: Style.space(10)
            anchors.right: shortcutBadge.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText.length > 0 ? root.filterText : tr("Search for apps…")
            textFormat: Text.PlainText
            color: root.foreground
            opacity: root.filterText.length > 0 ? 1 : 0.5
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          // Plain hint text like the mockup's "⌘ K" (no pill behind it).
          Text {
            id: shortcutBadge
            anchors.right: parent.right
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            text: "SUPER + S"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // Category pills — click to filter, wheel-scroll over the row to
        // cycle (a lightweight gesture, real Flickable/MouseArea wheel
        // handling, not a fabricated API). The wheel catcher is a sibling
        // of the Row, not a child of it — Row positions children by
        // setting their x itself, which conflicts with a child that
        // anchors.fill: parent (its own anchor and Row's positioning
        // fight over x/width), and every pill after it collapsed onto
        // the same spot as a result.
        Item {
          width: parent.width
          height: root.pillsSlot

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: function(wheel) { root.cycleCategory(wheel.angleDelta.y < 0 ? 1 : -1) }
          }

          // Space-between like the mockup: the leftover width is split
          // evenly between the pills (relayout() re-measures whenever a pill
          // or the row changes width).
          Row {
            id: pillRow
            anchors.fill: parent
            spacing: Style.space(8)

            function relayout() {
              var total = 0, n = 0
              for (var i = 0; i < children.length; i++) {
                if (children[i].isPill) { total += children[i].width; n++ }
              }
              spacing = n > 1 ? Math.max(Style.space(4), (width - total) / (n - 1)) : 0
            }
            onWidthChanged: relayout()

          Repeater {
            model: root.categoryDefs
            onItemAdded: Qt.callLater(pillRow.relayout)
            Rectangle {
              required property var modelData
              readonly property bool isPill: true
              onWidthChanged: Qt.callLater(pillRow.relayout)
              readonly property bool active: root.activeCategory === modelData.id
              height: root.pillsHeight
              width: pillLabel.implicitWidth + Style.space(20)
              radius: Style.space(10)
              color: active ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.26) : (pillMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent")

              Text {
                id: pillLabel
                anchors.centerIn: parent
                text: modelData.label
                textFormat: Text.PlainText
                color: active ? Color.accent : root.foreground
                opacity: active ? 1 : 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: pillMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setCategory(modelData.id)
              }
            }
          }
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.searchHeight - root.pillsSlot - root.contentSpacing * 2 - (root.recVisible ? root.recBlockHeight + root.contentSpacing : 0)

          GridView {
            id: appGrid
            anchors.fill: parent
            model: displayModel
            clip: true
            cellWidth: width / root.columns
            cellHeight: root.cellHeight
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              required property int index
              required property string appId
              required property string label
              required property string appIcon

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

              width: appGrid.cellWidth
              height: root.cellHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Column {
                anchors.centerIn: parent
                spacing: Style.space(6)
                width: parent.width - Style.space(8)

                Item {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: root.iconSize + Style.space(8)
                  height: root.iconSize + Style.space(8)

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.space(12)
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
                  }

                  Image {
                    anchors.centerIn: parent
                    width: root.iconSize
                    height: root.iconSize
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    source: root.iconSourceFor(appIcon)
                    asynchronous: true
                  }
                }

                Text {
                  width: parent.width
                  text: label
                  textFormat: Text.PlainText
                  color: hasCursor ? root.selectedText : root.foreground
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  maximumLineCount: 2
                  wrapMode: Text.WordWrap
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              MouseArea {
                id: tileMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.selectedIndex = index
                }
                onClicked: function(mouse) {
                  root.cursorActive = true
                  root.selectedIndex = index
                  if (mouse.button === Qt.RightButton) root.openAppMenu(appId, label, tileMouse, mouse)
                  else root.activateIndex(index)
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              text: root.filterText.length > 0 ? (tr("No matches for “") + root.filterText + "”") : tr("No apps in this category")
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }

        // Recommended — mockup's second block: header + 2-column list.
        Item {
          width: parent.width
          height: root.recBlockHeight
          visible: root.recVisible

          Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: root.foreground
            opacity: 0.12
          }

          Text {
            id: recTitle
            anchors.top: parent.top
            anchors.topMargin: Style.space(10)
            text: tr("Recommended")
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          // Real toggle: 6 entries <-> 12 (card grows/shrinks with them).
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: recTitle.verticalCenter
            text: (root.recExpanded ? tr("Show Less") : tr("Show More")) + " \u203A"
            textFormat: Text.PlainText
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall

            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.recExpanded = !root.recExpanded
                root.rebuildRecommended()
              }
            }
          }

          // Inset so the list lines up with the app grid's icon columns
          // (first-column icon left edge / last-column right edge) instead of
          // hugging the card's left padding.
          Grid {
            anchors.top: recTitle.bottom
            anchors.topMargin: Style.space(9)
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - Style.space(28)
            columns: 2
            rowSpacing: 0

            Repeater {
              model: recModel
              delegate: Item {
                required property string appId
                required property string label
                required property string appIcon
                required property string why
                width: parent.width / 2
                height: root.recRowHeight

                Rectangle {
                  anchors.fill: parent
                  anchors.margins: 2
                  radius: Style.space(8)
                  color: recMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"
                }

                Image {
                  id: recIcon
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(38)
                  height: Style.space(38)
                  fillMode: Image.PreserveAspectFit
                  sourceSize.width: width * Screen.devicePixelRatio
                  sourceSize.height: height * Screen.devicePixelRatio
                  source: root.iconSourceFor(appIcon)
                  asynchronous: true
                }

                Column {
                  anchors.left: recIcon.right
                  anchors.leftMargin: Style.space(10)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    width: parent.width
                    text: label
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    width: parent.width
                    text: why
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: root.foreground
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall - 1
                  }
                }

                MouseArea {
                  id: recMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) root.openAppMenu(appId, label, recMouse, mouse)
                    else root.launch(appId, label)
                  }
                }
              }
            }
          }
        }
      }

      // Right-click menu overlay: dismiss layer + the menu card.
      Item {
        id: appMenuLayer
        anchors.fill: parent
        visible: root.appMenu !== null
        z: 50

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: root.closeAppMenu()
        }

        Rectangle {
          id: appMenuCard
          readonly property real rowH: Style.space(32)
          width: Style.space(196)
          height: appMenuColumn.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          x: root.appMenu ? Math.max(Style.space(8), Math.min(root.appMenu.x, appMenuLayer.width - width - Style.space(8))) : 0
          y: root.appMenu ? Math.max(Style.space(8), Math.min(root.appMenu.y, appMenuLayer.height - height - Style.space(8))) : 0
          color: Qt.rgba(0.04, 0.08, 0.13, 0.94)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

          MouseArea { anchors.fill: parent; onClicked: {} }

          Column {
            id: appMenuColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(6)

            Text {
              width: parent.width
              leftPadding: Style.space(8)
              height: Style.space(24)
              verticalAlignment: Text.AlignVCenter
              text: root.appMenu ? root.appMenu.label : ""
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall - 1
            }

            Repeater {
              model: root.appMenuItems
              delegate: Rectangle {
                required property var modelData
                width: parent.width
                height: appMenuCard.rowH
                radius: Style.space(6)
                color: rowMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10) : "transparent"

                Text {
                  visible: modelData.kind === "setcat" && modelData.checked === true
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\u2713"
                  textFormat: Text.PlainText
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8) + (modelData.kind === "setcat" ? Style.space(20) : 0)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: modelData.danger ? "#ff6b6b" : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.runAppMenuItem(modelData)
                }
              }
            }
          }
        }
      }

      // Uninstall confirmation: dim layer + centred glass card.
      Item {
        id: deleteLayer
        anchors.fill: parent
        visible: root.deleteConfirmOpen
        z: 60

        Rectangle {
          anchors.fill: parent
          radius: root.cardRadius
          color: Qt.rgba(0.02, 0.04, 0.08, 0.55)
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: root.cancelDelete()
        }

        Rectangle {
          id: deleteCard
          anchors.centerIn: parent
          width: Style.space(300)
          height: deleteColumn.implicitHeight + Style.space(36)
          radius: root.cardRadius
          color: Qt.rgba(0.04, 0.08, 0.13, 0.96)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

          MouseArea { anchors.fill: parent; onClicked: {} }

          Column {
            id: deleteColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(18)
            spacing: Style.space(6)

            Text {
              width: parent.width
              text: tr("Uninstall ") + ((root.deleteTarget && root.deleteTarget.label) || "") + "?"
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              width: parent.width
              text: tr("This removes the package and its launcher entry from your system.")
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Item { width: 1; height: Style.space(10) }

            Row {
              anchors.right: parent.right
              spacing: Style.space(10)

              Rectangle {
                width: Style.space(96)
                height: Style.space(34)
                radius: Style.space(8)
                color: cancelMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                border.width: 1
                border.color: root.deleteFocus === 0 ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

                Text {
                  anchors.centerIn: parent
                  text: tr("Cancel")
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                MouseArea {
                  id: cancelMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.cancelDelete()
                }
              }

              Rectangle {
                width: Style.space(96)
                height: Style.space(34)
                radius: Style.space(8)
                color: uninstallMouse.containsMouse ? Qt.rgba(1, 0.42, 0.42, 0.30) : Qt.rgba(1, 0.42, 0.42, 0.18)
                border.width: 1
                border.color: root.deleteFocus === 1 ? Color.accent : Qt.rgba(1, 0.42, 0.42, 0.55)

                Text {
                  anchors.centerIn: parent
                  text: tr("Uninstall")
                  textFormat: Text.PlainText
                  color: "#ff8f8f"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                MouseArea {
                  id: uninstallMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.confirmDelete()
                }
              }
            }
          }
        }
      }
    }
  }
}
