import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Workspace Pager — each button shows a live miniature of the windows in that
// workspace, scaled proportionally to the monitor, positioned/sized to match
// their real on-screen layout, and labelled with the app's own icon so the
// pager actually tells you what's running instead of an arbitrary colour.
// Clicking a button switches to that workspace.
//
// Window geometry and workspace membership come from a short
// `hyprctl clients -j` poll. HyprlandToplevel.lastIpcObject is only a cache
// and can omit geometry until Quickshell fetches the window again.
//
// Icon resolution (entryFor/iconSourceFor/iconIndex below) is copied from
// orbital.dock's Dock.qml, which already solved this exact problem for the
// same shell — see that file's own header comment for why a manual XDG icon
// scan is needed on top of Quickshell.iconPath (it silently misses
// com.mitchellh.ghostty and files-native on this machine).
//
// Colour derivation (appColor) is now only a fallback tint for apps with no
// resolvable icon, and a deterministic hash of the app class name → HSL hue.

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // ---------------------------------------------------------- monitor size
  // Used to compute the scale factor: thumb / monitor = miniature scale.
  // Falls back to sensible defaults if Hyprland.monitors isn't populated yet.
  readonly property real monitorW: {
    var ms = Hyprland.monitors && Hyprland.monitors.values
    return (ms && ms.length > 0 && ms[0].width > 0) ? ms[0].width : 1366
  }
  readonly property real monitorH: {
    var ms = Hyprland.monitors && Hyprland.monitors.values
    return (ms && ms.length > 0 && ms[0].height > 0) ? ms[0].height : 768
  }

  // --------------------------------------------------------- thumbnail size
  // The chip's height is hard-capped by the bar's own height (root.barSize,
  // ~26px by default) — anything taller gets silently clipped by the bar,
  // which is what made the very first version of this widget look like flat
  // colour blocks (the bezel and the workspace-number badge were being cut
  // off, invisible, never a rendering bug). So we size DOWN from the bar
  // height, not up from an arbitrary width like the original attempt did.
  readonly property real chipBezel: 2
  readonly property real chipH: root.barSize
  readonly property real thumbH: Math.max(8, chipH - chipBezel * 2)
  readonly property real thumbW: Math.round(thumbH * monitorW / monitorH)
  readonly property real thumbScale: thumbH / monitorH

  // Full chip footprint including the bezel, used to size the click target.
  readonly property real chipW: thumbW + chipBezel * 2

  // Corner radius of the workspace chip (not of the window rects inside).
  readonly property real chipRadius: Math.min(chipH / 2, Style.space(3))

  // ------------------------------------------------ deterministic app colour
  // Maps an app class string to a unique, visually distinct HSL colour.
  // The hash is a simple djb2 variant — cheap and collision-free enough for
  // the dozen-ish different app classes a user has open at once.
  function appColor(cls) {
    var s = String(cls || "unknown")
    var hash = 5381
    for (var i = 0; i < s.length; i++) {
      hash = ((hash << 5) + hash + s.charCodeAt(i)) & 0x7fffffff
    }
    // Spread hues across the full wheel; keep saturation and lightness
    // moderate so colours are distinct but don't scream.
    var hue = (hash % 360 + 360) % 360
    return Qt.hsla(hue / 360, 0.5, 0.52, 0.85)
  }

  // ------------------------------------------------------------ app icons
  // Copied from orbital.dock's Dock.qml (same shell, already-solved problem)
  // — resolves a window's app class to a real, themed icon file.
  function keyFor(cls) {
    var id = String(cls || "").trim().toLowerCase()
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

  function iconSourceFor(cls) {
    var entry = root.entryFor(root.keyFor(cls))
    var value = String((entry && entry.icon) || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var indexed = root.iconIndex[value]
    if (indexed) return Util.fileUrl(indexed)
    return Quickshell.iconPath(value, true)
  }

  // Same manual XDG icon scan as orbital.dock — Quickshell's own theme-chain
  // walk misses some real, installed icons (see file header comment).
  property var iconIndex: ({})
  property var pendingIconIndex: ({})

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
    command: ["bash", "-c", [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'for ext in svg png; do',
      '  for base in $dirs; do',
      '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
      'done'
    ].join(' ')]
    stdout: SplitParser { onRead: function(line) { root.indexIconLine(line) } }
    onStarted: root.pendingIconIndex = ({})
    onExited: { root.iconIndex = root.pendingIconIndex }
    Component.onCompleted: running = true
  }

  // ---------------------------------------------------- workspace list logic
  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }
    ids.sort(function(a, b) { return a - b })
    return ids
  }

  function nextWorkspaceId() {
    var ids = root.workspaceIds()
    var next = ids[ids.length - 1] + 1
    return next <= 10 ? next : 0
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // Human-readable app name for a tooltip, preferring the .desktop entry's
  // display name over the raw window class (e.g. "Slack" not
  // "chrome-app.slack.com__client_-Default").
  function appLabel(cls) {
    var entry = root.entryFor(root.keyFor(cls))
    return (entry && entry.name) ? entry.name : String(cls || "?")
  }

  function windowLabelsFor(wsId) {
    var wins = root.windowsForWorkspace(wsId)
    var labels = []
    for (var i = 0; i < wins.length; i++) {
      labels.push(root.appLabel(wins[i].class || ""))
    }
    return labels.join(", ")
  }

  // Hyprland's IPC event stream has no dedicated "resize" event — dragging a
  // window's border doesn't fire movewindow, workspace, or anything else
  // Quickshell listens to, so HyprlandToplevel.lastIpcObject's cached at/size
  // goes stale until some unrelated event happens to refresh it. Confirmed
  // live: `hyprctl clients -j` reflects a resize instantly, but neither the
  // miniature nor Hyprland.refreshToplevels() picked it up — so this polls
  // the same JSON Quickshell itself reads, directly, on a short interval,
  // and the per-window geometry below uses this live client snapshot.
  property var liveClients: []

  Process {
    id: clientsPoll
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var list = JSON.parse(text)
          root.liveClients = Array.isArray(list) ? list : []
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: { if (!clientsPoll.running) clientsPoll.running = true }
  }

  // ------------------------------------------- window list helpers
  // Return live Hyprland client objects for this workspace. This avoids
  // depending on a possibly incomplete HyprlandToplevel.lastIpcObject cache.
  function windowsForWorkspace(wsId) {
    var result = []
    var clients = root.liveClients || []
    for (var i = 0; i < clients.length; i++) {
      var client = clients[i]
      if (!client || !client.workspace || client.workspace.id !== wsId) continue
      if (client.hidden || client.mapped === false) continue
      if (!client.at || !client.size || client.size[0] <= 0 || client.size[1] <= 0) continue
      result.push(client)
    }
    return result
  }

  // ----------------------------------------------------------------- layout
  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length + (root.nextWorkspaceId() > 0 ? 1 : 0)
    columnSpacing: root.vertical ? 0 : Style.space(2)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      Item {
        id: wsItem
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        // The chip is wider than it is tall (16:9-ish) but never taller than
        // the bar itself — see chipH/thumbH above.
        implicitWidth: button.implicitWidth
        implicitHeight: button.implicitHeight

        // Invisible click target that covers the chip area.
        WidgetButton {
          id: button
          bar: root.bar
          text: ""
          labelVisible: false
          hasVisualContent: true
          // A few extra px of click target beyond the chip's own bezel.
          fixedWidth: root.chipW + 4
          fixedHeight: root.barSize
          tooltipText: wsItem.occupied ? root.windowLabelsFor(wsItem.modelData) : ""
          onPressed: function() { root.focusWorkspace(wsItem.modelData) }
        }

        // ------------------------------------------------ workspace chip
        Rectangle {
          id: chip
          anchors.centerIn: parent
          width: root.chipW
          height: root.chipH
          radius: root.chipRadius

          // Background: a translucent tint of the foreground colour, not a
          // flat Color.background fill — the bar's own background usually
          // *is* Color.background, so filling the chip with the exact same
          // colour made the bezel invisible against it no matter the size.
          // A translucent tint always contrasts a little, regardless of theme.
          color: wsItem.focused
            ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
            : Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b,
                      wsItem.occupied ? 0.10 : 0.05)

          // Always-visible border so chips stay legible as separate tiles —
          // this is what stops a two-window (tiled) workspace from reading
          // as two unrelated workspace buttons. Accent + thicker when focused.
          border.width: wsItem.focused ? 2 : 1
          border.color: wsItem.focused
            ? Color.accent
            : Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.32)

          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on border.color { ColorAnimation { duration: 120 } }

          // ------------------------------------------ window miniatures
          // Clip so window rects can't overflow the chip.
          Item {
            id: miniature
            anchors.centerIn: parent
            width: root.thumbW
            height: root.thumbH
            clip: true

            // Re-evaluate whenever toplevels change.
            // `workspace.toplevels` is the reactive list; touching its
            // .values triggers a binding update on the Repeater model.
            Repeater {
              model: {
                return root.windowsForWorkspace(wsItem.modelData)
              }

              Rectangle {
                required property var modelData  // hyprctl client object

                readonly property var geo: modelData
                readonly property var at: geo ? geo.at : null
                readonly property var sz: geo ? geo.size : null
                readonly property bool valid: at && sz && sz[0] > 0 && sz[1] > 0

                visible: valid

                // Scale monitor coordinates to thumbnail coordinates, then
                // inset by half a pixel gap on each side so adjacent/tiled
                // windows (and a single maximized window against the chip
                // bezel) always show a hairline seam instead of fusing into
                // one undifferentiated colour block.
                readonly property real gap: 1
                x: valid ? Math.round(at[0] * root.thumbScale) + gap : 0
                y: valid ? Math.round(at[1] * root.thumbScale) + gap : 0
                width:  valid ? Math.max(2, Math.round(sz[0] * root.thumbScale) - gap * 2) : 0
                height: valid ? Math.max(2, Math.round(sz[1] * root.thumbScale) - gap * 2) : 0

                readonly property color baseColor: root.appColor(geo ? (geo.class || "") : "")

                radius: 2
                // Faint tint (not the loud full-strength hue from before) —
                // now just a background so a window keeps *some* identity
                // even before its icon loads, or if it has none. The icon
                // below is what actually says "what's running".
                color: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.35)

                // Thin inner border so touching windows stay distinguishable.
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.3)

                readonly property string iconSource: root.iconSourceFor(geo ? geo.class : "")
                readonly property real iconSize: Math.min(width, height) - 4

                // Only draw the icon if it actually fits with some padding —
                // a sliver of a tiled window falls back to the plain tint.
                Image {
                  anchors.centerIn: parent
                  visible: parent.iconSource.length > 0 && parent.iconSize >= 8
                  source: parent.iconSource
                  sourceSize.width: Math.round(parent.iconSize)
                  sourceSize.height: Math.round(parent.iconSize)
                  width: Math.round(parent.iconSize)
                  height: Math.round(parent.iconSize)
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                  asynchronous: true
                }
              }
            }
          }

          // Workspace number — small badge in the bottom-right corner of the
          // chip. Sits on its own opaque backdrop (not bare text) so it stays
          // legible over any window colour underneath. Must stay fully inside
          // the chip: the chip already equals root.barSize, so anything that
          // pokes outside gets clipped by the bar itself (the bug that made
          // the very first version invisible).
          Rectangle {
            id: numberBadge
            anchors {
              right: parent.right
              bottom: parent.bottom
              margins: 1
            }
            width: numberLabel.implicitWidth + 4
            height: numberLabel.implicitHeight + 2
            radius: height / 2
            color: wsItem.focused ? Color.accent : Color.background
            border.width: 1
            border.color: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.25)

            Text {
              id: numberLabel
              anchors.centerIn: parent
              text: wsItem.modelData === 10 ? "0" : String(wsItem.modelData)
              textFormat: Text.PlainText
              color: wsItem.focused ? Color.background : button.foreground
              font.family: button.fontFamily
              font.pixelSize: Math.max(7, Style.font.bodySmall - 3)
              font.bold: wsItem.focused
            }
          }
        }
      }
    }

    // "+" button — creates / jumps to the next workspace.
    Item {
      visible: root.nextWorkspaceId() > 0
      implicitWidth: plusButton.implicitWidth
      implicitHeight: plusButton.implicitHeight

      WidgetButton {
        id: plusButton
        bar: root.bar
        text: ""
        labelVisible: false
        hasVisualContent: true
        fixedWidth: root.chipW + 4
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(root.nextWorkspaceId()) }
      }

      Text {
        anchors.centerIn: parent
        text: "+"
        textFormat: Text.PlainText
        color: plusButton.foreground
        opacity: 0.45
        font.family: plusButton.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
