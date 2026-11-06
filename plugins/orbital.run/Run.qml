// Orbital Run — a Windows-style Run dialog (Super+R): one compact card,
// a focused text field, live suggestions and a persistent MRU history.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "AppSearch.js" as AppSearch

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string query: ""
  property string errorText: ""
  property int selectedIndex: -1
  property int historyNav: -1
  property bool navigatedByArrows: false
  property var history: []
  property var pathBins: []

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(1)))
  property color scrim: "transparent"
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color dangerText: Color.urgent
  property string fontFamily: Style.font.family
  property int contentMargin: Style.spacing.panelPadding
  property int inputHeight: Style.space(42)
  property int rowHeight: Style.space(34)
  property int headerHeight: Style.space(26)
  property int buttonHeight: Style.space(32)
  readonly property int maxSuggestRows: 6
  property int cardWidth: Math.min(Style.space(540), panel.width - Style.gapsOut * 4)

  readonly property string fallbackIconUrl: Util.fileUrl(
    Quickshell.env("HOME") + "/.config/omarchy/plugins/orbital.ui/icons/application-x-executable-symbolic.svg"
  )

  FontMetrics {
    id: bodyFontMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  TextMetrics {
    id: sampleTextMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    text: "Run Cancel Visual Studio Code"
  }

  // Optical vertical offset if the active font's glyphs sit below the vertical center of its line box
  readonly property real textVerticalOffset: {
    var boxCenter = bodyFontMetrics.height / 2
    var inkCenter = sampleTextMetrics.tightBoundingRect.y + sampleTextMetrics.tightBoundingRect.height / 2
    var diff = boxCenter - inkCenter
    return (isFinite(diff) && Math.abs(diff) <= 8) ? Math.round(diff) : 0
  }

  // ------------------------------------------------------------ MRU store
  readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/orbital-run.json"
  readonly property int historyLimit: 30

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var d = JSON.parse(text())
        root.history = (d && d.history && d.history.length !== undefined) ? d.history : []
      } catch (e) { root.history = [] }
      if (root.opened) root.rebuildSuggestions()
    }
    onLoadFailed: root.history = []
    Component.onCompleted: {
      reload()
      Qt.callLater(root.runSelfTests)
    }
  }

  function recordHistory(command) {
    var value = String(command || "").trim()
    if (!value) return
    var list = []
    var at = -1
    for (var i = 0; i < root.history.length; i++)
      if (String(root.history[i]) === value) { at = i; break }
    for (var j = 0; j < root.history.length; j++)
      if (j !== at) list.push(root.history[j])
    list.unshift(value)
    if (list.length > root.historyLimit) list = list.slice(0, root.historyLimit)
    root.history = list
    root.saveHistory()
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify({ version: 1, history: root.history }, null, 2) + "\n")
  }

  // ------------------------------------------------------------ PATH index
  property var pendingBins: null

  function indexBinLine(line) {
    var value = String(line || "").trim()
    if (value.length === 0 || value.indexOf("/") >= 0) return
    if (root.pendingBins && root.pendingBins[value] === undefined)
      root.pendingBins[value] = true
  }

  Process {
    id: pathIndexScan
    command: [
      "bash", "-c",
      'for d in $(printf %s "$PATH" | tr ":" " "); do ls -1 "$d" 2>/dev/null; done | sort -u'
    ]
    stdout: SplitParser { onRead: function(line) { root.indexBinLine(line) } }
    onStarted: root.pendingBins = ({})
    onExited: {
      var names = []
      for (var k in root.pendingBins) names.push(k)
      names.sort()
      root.pathBins = names
      root.pendingBins = null
      if (root.opened) root.rebuildSuggestions()
      root.runSelfTests()
    }
    Component.onCompleted: running = true
  }

  // ------------------------------------------------------------ icon index
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
      if (root.opened) root.rebuildSuggestions()
    }
    Component.onCompleted: running = true
  }

  function iconSourceFor(icon) {
    var value = String(icon || "")
    if (value.length === 0) return root.fallbackIconUrl
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var indexed = root.iconIndex[value]
    if (indexed) return Util.fileUrl(indexed)
    var themed = Quickshell.iconPath(value, true)
    return (themed && themed.length > 0) ? themed : root.fallbackIconUrl
  }

  // ------------------------------------------------------------ dispatch
  function appEntries() {
    return (DesktopEntries.applications && DesktopEntries.applications.values) || []
  }

  function isGuiAppEntry(entry) {
    if (!entry) return false
    if (entry.runInTerminal === true || entry.terminal === true) return false
    return true
  }

  function entryById(id) {
    var wanted = String(id || "").trim().toLowerCase()
    if (!wanted) return null
    var values = root.appEntries()
    for (var i = 0; i < values.length; i++) {
      var own = String(values[i].id || "").toLowerCase()
      var bare = own.slice(-8) === ".desktop" ? own.slice(0, -8) : own
      if (own === wanted || bare === wanted || bare.slice(-(wanted.length + 1)) === "." + wanted) {
        if (root.isGuiAppEntry(values[i])) return values[i]
      }
    }
    return null
  }

  function entryByName(name) {
    var wanted = String(name || "").trim().toLowerCase()
    if (!wanted) return null
    var values = root.appEntries()
    for (var i = 0; i < values.length; i++) {
      if (AppSearch.entryName(values[i]).toLowerCase() === wanted && root.isGuiAppEntry(values[i]))
        return values[i]
    }
    return null
  }

  function findApp(text) {
    var full = String(text || "").trim()
    if (!full) return null
    var app = root.entryById(full)
    if (!app) app = root.entryByName(full)
    if (app) return app
    var head = root.firstToken(full)
    if (head && head !== full) {
      app = root.entryById(head)
      if (!app) app = root.entryByName(head)
    }
    return app
  }

  function isUrlLike(text) {
    var s = String(text || "").trim()
    return /^[a-z][a-z0-9+.-]*:\/\//i.test(s) || /^www\./i.test(s) || /^mailto:/i.test(s)
  }

  function trimLabel(value) {
    var s = String(value || "").replace(/[\x00-\x1f\x7f]/g, " ").trim()
    var maxLength = 48
    if (s.length > maxLength) s = s.slice(0, maxLength) + "\u2026"
    return s
  }

  function firstToken(text) {
    var s = String(text || "").trim()
    if (!s) return ""
    var token = ""
    var quote = ""
    for (var i = 0; i < s.length; i++) {
      var ch = s.charAt(i)
      if (quote) {
        if (ch === quote) { quote = ""; break }
        token += ch
      } else if (ch === '"' || ch === "'") {
        quote = ch
      } else if (/\s/.test(ch)) {
        if (quote === "" && token.length === 0) continue
        break
      } else {
        token += ch
      }
    }
    return token
  }

  function classify(text) {
    // Returns { kind, app, errorMessage } — kind: url|app|path|command|none.
    var cmd = String(text || "").trim()
    if (!cmd) return { kind: "none", app: null, errorMessage: "" }

    if (root.isUrlLike(cmd))
      return { kind: "url", app: null, errorMessage: "" }

    // Check full string first (so multi-word app names like "Visual Studio Code" match!),
    // then fall back to firstToken only if there are no spaces or if full didn't match.
    var app = root.entryById(cmd) || root.entryByName(cmd)
    if (!app && cmd.indexOf(" ") === -1) {
      var headOnly = root.firstToken(cmd)
      app = root.entryById(headOnly) || root.entryByName(headOnly)
    }
    if (app)
      return { kind: "app", app: app, errorMessage: "" }

    if (/^[~/.]/.test(cmd))
      return { kind: "path", app: null, errorMessage: "" }

    var head = root.firstToken(cmd)
    var search = head.toLowerCase()
    var isBin = false
    for (var i = 0; i < root.pathBins.length; i++)
      if (root.pathBins[i].toLowerCase() === search) { isBin = true; break }
    if (isBin || root.pathBins.length === 0)
      return { kind: "command", app: null, errorMessage: "" }

    return { kind: "none", app: null, errorMessage: "Could not find \u201C" + cmd + "\u201D" }
  }

  function launchApp(entry) {
    var rawId = String((entry && entry.id) || "").trim()
    if (!rawId) return
    var bareId = rawId.slice(-8) === ".desktop" ? rawId.slice(0, -8) : rawId
    var desktopFile = bareId + ".desktop"
    if (root.shell && root.shell.appLibrary && typeof root.shell.appLibrary.launch === "function") {
      root.shell.appLibrary.launch(bareId, AppSearch.entryName(entry))
      return
    }
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(desktopFile))
  }

  function launchCommandInTerminal(cmd) {
    var script = String(cmd) + '; code=$?; if (( code != 130 )); then printf "\\n[exit %d] Press any key to close..." "$code"; read -r -n 1 -s; fi'
    Util.execArgv([
      "setsid", "uwsm-app", "--",
      "xdg-terminal-exec",
      "--app-id=org.omarchy.terminal",
      "--title=Run: " + String(cmd),
      "-e", "bash", "-lc", script
    ])
  }

  function execute(text) {
    var cmd = String(text !== undefined ? text : root.query).trim()
    if (!cmd.length) { root.errorText = ""; return false }
    var verdict = root.classify(cmd)
    if (verdict.kind === "none") {
      root.errorText = verdict.errorMessage
      return false
    }
    root.errorText = ""
    if (verdict.kind === "app" && verdict.app) {
      root.launchApp(verdict.app)
    } else if (verdict.kind === "url") {
      var targetUrl = /^www\./i.test(cmd) ? ("https://" + cmd) : cmd
      Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote(targetUrl))
    } else if (verdict.kind === "path") {
      var home = Quickshell.env("HOME")
      var path = cmd
      if (path.charAt(0) === "~") path = home + path.slice(1)
      Util.execDetached("xdg-open " + Util.shellQuote(path) + " 2>/dev/null || notify-send -u critical -t 4000 Run " + Util.shellQuote("Could not open: " + path))
    } else {
      root.launchCommandInTerminal(cmd)
    }
    root.recordHistory(cmd)
    root.close()
    return true
  }

  function submitCurrent() {
    var typed = String(field.text || "").trim()
    if (root.selectedIndex >= 0 && root.selectedIndex < sugModel.count) {
      var row = sugModel.get(root.selectedIndex)
      if (!typed.length || root.navigatedByArrows) {
        root.activateSuggestion(root.selectedIndex)
        return
      }
      var verdict = root.classify(typed)
      var typedLower = typed.toLowerCase()
      var matchesTopApp = row && row.kind === "app" && typed.indexOf(" ") === -1 &&
        (String(row.label || "").toLowerCase().indexOf(typedLower) >= 0 ||
         String(row.appId || "").toLowerCase().indexOf(typedLower) >= 0)
      if (verdict.kind === "none" && matchesTopApp) {
        root.activateSuggestion(root.selectedIndex)
        return
      }
    }
    root.execute(typed)
  }

  // ------------------------------------------------------------ suggestions
  ListModel { id: sugModel }

  function rebuildSuggestions() {
    sugModel.clear()
    var q = root.query.trim().toLowerCase()
    var seen = {}

    function push(row) {
      var key = String(row.label || "") + "|" + String(row.subtext || "")
      if (seen[key]) return
      seen[key] = true
      sugModel.append(row)
    }

    if (!q.length) {
      for (var h = 0; h < root.history.length; h++) {
        if (sugModel.count >= root.maxSuggestRows) break
        var histCmd = String(root.history[h])
        var histApp = root.entryById(histCmd) || root.entryByName(histCmd)
        push({
          label: histCmd,
          subtext: "History",
          kind: histApp ? "app" : "command",
          appId: histApp ? String(histApp.id || "") : "",
          icon: histApp ? root.iconSourceFor(String(histApp.icon || "")) : root.iconSourceFor(""),
          raw: histCmd
        })
      }
      root.selectedIndex = sugModel.count > 0 ? 0 : -1
      return
    }

    // Apps first (fuzzy, top 3)
    var values = root.appEntries()
    var rows = AppSearch.sortedEntries(values, root.query, null)
    for (var i = 0; i < rows.length; i++) {
      if (sugModel.count >= 3) break
      var entry = rows[i].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      push({
        label: root.trimLabel(AppSearch.entryName(entry)),
        subtext: "App",
        kind: "app",
        appId: appId,
        icon: root.iconSourceFor(String(entry.icon || "")),
        raw: AppSearch.entryName(entry)
      })
    }

    // Then MRU substrings, most recent first.
    for (var j = 0; j < root.history.length; j++) {
      if (sugModel.count >= 6) break
      var item = String(root.history[j])
      if (item.toLowerCase().indexOf(q) < 0) continue
      var itemApp = root.entryById(item) || root.entryByName(item)
      push({
        label: item,
        subtext: "History",
        kind: itemApp ? "app" : "command",
        appId: itemApp ? String(itemApp.id || "") : "",
        icon: itemApp ? root.iconSourceFor(String(itemApp.icon || "")) : root.iconSourceFor(""),
        raw: item
      })
    }

    // Then PATH binaries by prefix.
    for (var k = 0; k < root.pathBins.length; k++) {
      if (sugModel.count >= root.maxSuggestRows) break
      var bin = root.pathBins[k]
      if (bin.toLowerCase().indexOf(q) !== 0) continue
      push({
        label: bin,
        subtext: "Command",
        kind: "command",
        appId: "",
        icon: root.iconSourceFor(""),
        raw: bin
      })
    }

    root.selectedIndex = sugModel.count > 0 ? 0 : -1
  }

  function moveSuggestion(delta) {
    var total = sugModel.count
    if (total > 1) {
      root.navigatedByArrows = true
      if (root.selectedIndex < 0) {
        root.selectedIndex = delta > 0 ? 0 : total - 1
      } else {
        root.selectedIndex = (root.selectedIndex + delta + total) % total
      }
      return
    }
    // When there is 0 or 1 suggestion, Up/Down cycles through MRU history into the input box
    if (root.history.length > 0) {
      var next = root.historyNav + delta
      if (next < 0) next = root.history.length - 1
      if (next >= root.history.length) next = 0
      root.historyNav = next
      var recalled = String(root.history[next])
      root.query = recalled
      if (field && field.text !== recalled) field.text = recalled
      if (field) field.cursorPosition = field.text.length
      root.errorText = ""
      root.rebuildSuggestions()
      return
    }
    if (total === 1) {
      root.selectedIndex = 0
      root.completeSuggestion()
    }
  }

  function activateSuggestion(index) {
    if (index < 0 || index >= sugModel.count) return
    var row = sugModel.get(index)
    if (!row) return
    if (row.kind === "app" && row.appId) {
      var app = root.entryById(row.appId) || root.findApp(row.raw || row.label)
      if (app) {
        root.errorText = ""
        root.launchApp(app)
        root.recordHistory(String(row.raw || row.label))
        root.close()
        return
      }
    }
    root.execute(row.raw || row.label)
  }

  function completeSuggestion() {
    if (sugModel.count === 0) return
    var idx = root.selectedIndex >= 0 && root.selectedIndex < sugModel.count ? root.selectedIndex : 0
    var row = sugModel.get(idx)
    if (!row) return
    var target = String(row.raw || row.label)
    if (field.text === target && sugModel.count > 1) {
      idx = (idx + 1) % sugModel.count
      root.selectedIndex = idx
      row = sugModel.get(idx)
      target = String(row.raw || row.label)
    }
    root.setQuery(target)
    if (field) {
      field.forceActiveFocus()
      field.cursorPosition = field.text.length
    }
  }

  function setQuery(next) {
    root.query = next
    if (field && field.text !== next) field.text = next
    root.historyNav = -1
    root.navigatedByArrows = false
    root.errorText = ""
    root.rebuildSuggestions()
  }

  function ensureFieldFocus() {
    if (!root.opened) return
    field.forceActiveFocus()
    field.cursorVisible = true
  }

  Timer {
    id: focusTimer
    interval: 40
    repeat: false
    onTriggered: root.ensureFieldFocus()
  }

  // ------------------------------------------------------------ open/close
  function open(payloadJson) {
    root.opened = true
    root.query = ""
    if (field) field.text = ""
    root.errorText = ""
    root.historyNav = -1
    root.navigatedByArrows = false
    root.rebuildSuggestions()
    if (root.pathBins.length === 0 && !pathIndexScan.running) pathIndexScan.running = true
    var payload = null
    try { payload = payloadJson ? JSON.parse(payloadJson) : null } catch (e) {}
    if (payload && typeof payload.text === "string" && payload.text.length > 0) root.setQuery(payload.text)
    if (payload && payload.run === true) {
      Qt.callLater(function() { root.submitCurrent() })
    } else {
      Qt.callLater(root.ensureFieldFocus)
      focusTimer.restart()
    }
  }

  function close() {
    root.opened = false
  }

  function toggle(payloadJson) {
    if (root.opened) root.close()
    else root.open(payloadJson)
  }

  function handleKeyEvent(event) {
    if (event.key === Qt.Key_Escape) {
      root.close()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.submitCurrent()
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      root.moveSuggestion(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      root.moveSuggestion(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      root.completeSuggestion()
      event.accepted = true
    }
  }

  function runSelfTests() {
    var vsVerdict = root.classify("Visual Studio Code")
    var pingVerdict = root.classify("ping 8.8.8.8")
    var urlVerdict = root.classify("https://omarchy.org")
    var pathVerdict = root.classify("~/Downloads")
    var badVerdict = root.classify("nonexistent-command-xyz-999")
    console.log(
      "orbital.run v4 self-test:",
      "bins=" + root.pathBins.length,
      "vscode=" + vsVerdict.kind,
      "ping=" + pingVerdict.kind,
      "url=" + urlVerdict.kind,
      "path=" + pathVerdict.kind,
      "bad=" + badVerdict.kind
    )
  }

  // ------------------------------------------------------------ window
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "orbital-run"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: {
      if (visible) {
        Qt.callLater(root.ensureFieldFocus)
        focusTimer.restart()
      }
    }

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
      height: contentColumn.implicitHeight + card.contentTopInset + card.contentBottomInset
      radius: Style.cornerRadius
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.bottomMargin: Style.bar.sizeHorizontal + Style.gapsOut * 4
      anchors.leftMargin: Style.gapsOut * 4
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea {
        anchors.fill: parent
        onClicked: root.ensureFieldFocus()
      }

      Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        anchors.topMargin: card.contentTopInset
        spacing: Style.space(12)

        // Header — glyph + title, Esc hint on the right.
        Item {
          width: parent.width
          height: root.headerHeight

          Image {
            id: headerIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18)
            height: Style.space(18)
            fillMode: Image.PreserveAspectFit
            opacity: 0.9
            source: root.fallbackIconUrl
          }

          Text {
            anchors.left: headerIcon.right
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.textVerticalOffset
            text: "Run"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            verticalAlignment: Text.AlignVCenter
          }

          Rectangle {
            id: escBadge
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: escText.implicitWidth + Style.space(12)
            height: Style.space(22)
            radius: Math.max(0, Style.cornerRadius - 4)
            color: escMouse.containsMouse
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
              : "transparent"

            Text {
              id: escText
              anchors.centerIn: parent
              anchors.verticalCenterOffset: root.textVerticalOffset
              text: "ESC"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: escMouse.containsMouse ? 0.85 : 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              verticalAlignment: Text.AlignVCenter
            }

            MouseArea {
              id: escMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.close()
            }
          }
        }

        // Input row — real TextInput with properly centered cursor and placeholder.
        Item {
          width: parent.width
          height: root.inputHeight

          Rectangle {
            anchors.fill: parent
            radius: Math.max(0, Style.cornerRadius - 2)
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.07)
            border.width: 1
            border.color: field.activeFocus
              ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.55)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
          }

          TextInput {
            id: field
            focus: true
            activeFocusOnTab: true
            selectByMouse: true
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.textVerticalOffset
            height: parent.height
            verticalAlignment: TextInput.AlignVCenter
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            clip: true
            selectedTextColor: root.selectedText
            selectionColor: root.selectedBackground

            Keys.priority: Keys.BeforeItem
            Keys.onTabPressed: function(event) {
              root.completeSuggestion()
              event.accepted = true
            }
            Keys.onBacktabPressed: function(event) {
              root.completeSuggestion()
              event.accepted = true
            }
            Keys.onPressed: function(event) {
              root.handleKeyEvent(event)
            }

            onTextChanged: {
              if (root.query !== field.text) root.setQuery(field.text)
            }

            onActiveFocusChanged: if (activeFocus) cursorVisible = true
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.textVerticalOffset
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            text: "Type a program name, folder, document or URL\u2026"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.4
            visible: root.query.length === 0
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }
        }

        // Error strip — inline failure message inside the card.
        Item {
          width: parent.width
          height: Style.space(18)
          visible: root.errorText.length > 0

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.textVerticalOffset
            text: root.errorText
            textFormat: Text.PlainText
            color: root.dangerText
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }
        }

        // Suggestions.
        Column {
          width: parent.width
          spacing: Style.space(2)
          visible: sugModel.count > 0

          Repeater {
            model: sugModel

            Item {
              width: parent.width
              height: root.rowHeight
              required property int index
              required property string label
              required property string subtext
              required property string kind
              required property string appId
              required property string icon
              required property string raw
              property bool selected: index === root.selectedIndex
              z: 1

              Rectangle {
                anchors.fill: parent
                radius: Math.max(0, Style.cornerRadius - 2)
                color: selected
                  ? root.selectedBackground
                  : (rowMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06) : "transparent")
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = index
                onClicked: root.activateSuggestion(index)
              }

              Image {
                id: rowIcon
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(18)
                height: Style.space(18)
                fillMode: Image.PreserveAspectFit
                source: icon
                visible: status === Image.Ready
              }

              Text {
                id: rowLabel
                anchors.left: rowIcon.right
                anchors.leftMargin: Style.space(10)
                anchors.right: rowSub.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: root.textVerticalOffset
                text: label
                textFormat: Text.PlainText
                color: selected ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
              }

              Text {
                id: rowSub
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: root.textVerticalOffset
                text: subtext
                textFormat: Text.PlainText
                color: selected ? root.selectedText : root.foreground
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                verticalAlignment: Text.AlignVCenter
              }
            }
          }
        }

        // Footer — interactive shortcut hints on the left, OK / Cancel on the right.
        Item {
          width: parent.width
          height: root.buttonHeight

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Rectangle {
              height: Style.space(22)
              width: hintRun.implicitWidth + Style.space(8)
              radius: Math.max(0, Style.cornerRadius - 4)
              color: hintRunMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"

              Text {
                id: hintRun
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.textVerticalOffset
                text: "\u21B5 Run"
                textFormat: Text.PlainText
                color: root.foreground
                opacity: hintRunMouse.containsMouse ? 0.85 : 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: hintRunMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.submitCurrent()
              }
            }

            Rectangle {
              height: Style.space(22)
              width: hintHist.implicitWidth + Style.space(8)
              radius: Math.max(0, Style.cornerRadius - 4)
              color: hintHistMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"

              Text {
                id: hintHist
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.textVerticalOffset
                text: "\u2191\u2193 History"
                textFormat: Text.PlainText
                color: root.foreground
                opacity: hintHistMouse.containsMouse ? 0.85 : 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: hintHistMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.moveSuggestion(1)
              }
            }

            Rectangle {
              height: Style.space(22)
              width: hintTab.implicitWidth + Style.space(8)
              radius: Math.max(0, Style.cornerRadius - 4)
              color: hintTabMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"

              Text {
                id: hintTab
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.textVerticalOffset
                text: "TAB Complete"
                textFormat: Text.PlainText
                color: root.foreground
                opacity: hintTabMouse.containsMouse ? 0.85 : 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: hintTabMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.completeSuggestion()
              }
            }
          }

          Rectangle {
            id: okButton
            readonly property bool canRun: root.query.trim().length > 0 || sugModel.count > 0
            anchors.right: cancelButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(56)
            height: parent.height
            radius: Math.max(0, Style.cornerRadius - 2)
            color: canRun
              ? Color.accent
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            opacity: okMouse.pressed ? 0.85 : (canRun ? 1 : 0.45)
            enabled: canRun

            MouseArea {
              id: okMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: okButton.canRun ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.submitCurrent()
            }

            Text {
              anchors.centerIn: parent
              anchors.verticalCenterOffset: root.textVerticalOffset
              text: "OK"
              textFormat: Text.PlainText
              color: okButton.canRun ? root.background : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          Rectangle {
            id: cancelButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(64)
            height: parent.height
            radius: Math.max(0, Style.cornerRadius - 2)
            color: cancelMouse.containsMouse
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
              : "transparent"
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
            opacity: cancelMouse.pressed ? 0.85 : 1

            MouseArea {
              id: cancelMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.close()
            }

            Text {
              anchors.centerIn: parent
              anchors.verticalCenterOffset: root.textVerticalOffset
              text: "Cancel"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
