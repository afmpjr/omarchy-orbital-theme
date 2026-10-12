import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "NotificationsModel.js" as Model
import "../orbital.ui" as OrbitalUi

// Bell for the bar. Owns the notification history: it polls omarchy's on-disk
// notification state (live popups + the 10-file history), merges what it finds
// into its own archive under ~/.local/state/omarchy/orbital-notifications/,
// and shows that archive in the panel below.
//
// Deliberately NOT backed by a plugin service: under a plugin bar
// (orbital.floating-bar) a widget's `bar.shell.serviceFor()` cannot reach
// another plugin's live service object (the facade is scoped to the bar
// plugin's own id), so cross-plugin state lives in files instead. File
// watchers keep every per-monitor instance converged without any IPC between
// them. Do Not Disturb is the one exception that stays live: it goes through
// the first-party proxy (`bar.shell.firstPartyServiceFor`), the same narrow
// proxy the stock bar's own Dnd indicator uses.
BarWidget {
  id: root
  function tr(s) { return OrbitalUi.OrbitalI18n.t(s) }
  moduleName: "orbital.notifications"

  readonly property string badgeMode: setting("badge", "Dot")
  readonly property int keepDays: setting("keepDays", 30)
  readonly property int maxItems: setting("maxItems", 1000)
  readonly property int panelWidth: setting("panelWidth", 420)

  readonly property string home: Quickshell.env("HOME")
  readonly property string storeDir: home + "/.local/state/omarchy/orbital-notifications/"
  readonly property string archivePath: storeDir + "archive.jsonl"
  readonly property string dismissedPath: storeDir + "dismissed.jsonl"
  readonly property string seenPath: storeDir + "seen"
  readonly property string importMarkerPath: storeDir + "imported"
  readonly property string ownImagesDir: storeDir + "images/"
  readonly property string omarchyStateDir: home + "/.local/state/omarchy/notifications/"
  readonly property string omarchyImagesDir: omarchyStateDir + "images/"
  readonly property string legacyArchivePath: home + "/.local/state/omarchy-notification-center/archive.jsonl"
  readonly property string legacyImagesDir: home + "/.local/state/omarchy-notification-center/images/"
  readonly property string dndSettingsPath: home + "/.local/state/omarchy/notifications.json"

  // Newest first. The panel reads this straight off its host widget.
  property var entries: []
  // Discarded keys (tombstones): dismissEntry()/clearAll() remove entries from
  // the archive, but omarchy's own history files still hold them, so without
  // this map the next 3 s poll would resurrect them. Persisted append-only in
  // dismissed.jsonl so discards survive restarts and converge across the
  // per-monitor instances via the file watcher below.
  property var dismissed: ({})
  property double seenMs: 0
  readonly property int unread: Model.unreadCount(entries, seenMs)

  // First-party DND proxy. Under orbital.floating-bar `bar` is the bar's own
  // root and `bar.shell` is the bar plugin's scoped shell, which carries bar
  // capabilities and therefore the prebuilt omarchy.notifications proxy. Under
  // the stock bar a third-party widget gets a capability-less facade, so this
  // is null there and the panel falls back to the read-only file state.
  readonly property var dndProxy: {
    var host = root.bar && root.bar.shell ? root.bar.shell : null
    if (!host || typeof host.firstPartyServiceFor !== "function") return null
    try {
      return host.firstPartyServiceFor("omarchy.notifications")
    } catch (e) {
      return null
    }
  }
  property bool dndFileState: false
  readonly property bool dnd: dndProxy ? dndProxy.doNotDisturb === true : dndFileState
  readonly property bool dndWritable: dndProxy !== null

  function toggleDnd() {
    if (dndProxy && typeof dndProxy.setDoNotDisturb === "function")
      dndProxy.setDoNotDisturb(!root.dnd)
  }

  // ---- Shape contract for shell.summon/hide/toggle routing: open/close/opened
  //      on the bar-widget root (same contract orbital.clock follows).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    markSeen()
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // Opening the center means everything in it has been seen: the bell clears
  // on the click itself, and the seen file converges the other instances.
  function markSeen() {
    root.seenMs = Date.now()
    seenView.setText(String(root.seenMs))
  }

  function clearAll() {
    var keys = root.entries.map(function (e) { return e.key })
    if (keys.length > 0) {
      root.dismissed = Model.trimDismissed(Model.addDismissed(root.dismissed, keys, Date.now()), dismissedCap(), root.keepDays, Date.now())
      appendDismissed(keys)
    }
    root.entries = []
    writeArchive()
    markSeen()
  }

  function dismissEntry(key) {
    var needle = String(key || "")
    if (!needle) return
    root.dismissed = Model.trimDismissed(Model.addDismissed(root.dismissed, [needle], Date.now()), dismissedCap(), root.keepDays, Date.now())
    appendDismissed([needle])
    root.entries = root.entries.filter(function (e) { return String(e.key || "") !== needle })
    writeArchive()
  }

  // Tombstones stay bounded: same age window as the archive, count capped at
  // (at least) 1000 so every key the archive could still hold stays covered.
  function dismissedCap() {
    return Math.max(1000, root.maxItems)
  }

  // Append-only so two per-monitor instances discarding at the same moment
  // never clobber each other (a full rewrite would last-writer-wins). Values
  // travel as argv, never interpolated into the shell script.
  function appendDismissed(keys) {
    var lines = Model.dismissedLines(keys, Date.now())
    if (lines.length === 0) return
    var command = ["bash", "-c",
      "f=\"$1\"; shift\nmkdir -p \"$(dirname \"$f\")\"\nfor l in \"$@\"; do printf '%s\\n' \"$l\" >> \"$f\"; done",
      "--", root.dismissedPath]
    for (var i = 0; i < lines.length; i++) command.push(lines[i])
    dismissAppendProc.command = command
    dismissAppendProc.running = true
  }

  function writeArchive() {
    var visible = Model.withoutDismissed(root.entries, root.dismissed)
    var trimmed = Model.trimEntries(visible, root.maxItems, root.keepDays, Date.now())
    root.entries = trimmed
    archiveView.setText(Model.serializeArchive(trimmed))
  }

  // Bounded directory read: the newest few dozen one-line JSON files, 64 KiB
  // each. A runaway sender cannot make this poll unbounded.
  function ingestNow() {
    if (ingestProc.running) return
    ingestProc.command = ["bash", "-c",
      "ls -1 \"$1\"/*.json \"$1\"/history/*.json 2>/dev/null | head -n 40 | " +
      "while IFS= read -r f; do head -c 65536 -- \"$f\" 2>/dev/null; echo; done",
      "--", root.omarchyStateDir]
    ingestProc.running = true
  }

  function ingestOmarchy(raw) {
    var rows = Model.withoutDismissed(Model.parseEntryLines(raw), root.dismissed)
    if (rows.length === 0) return
    var known = {}
    for (var i = 0; i < root.entries.length; i++) known[root.entries[i].key] = true
    var fresh = rows.filter(function (e) { return !known[e.key] })
    if (fresh.length === 0) return
    var merged = Model.mergeEntries(root.entries, fresh, root.dismissed)
    var planned = Model.planImageCopies(merged, root.omarchyImagesDir, root.ownImagesDir)
    runCopies(planned.copies)
    root.entries = Model.trimEntries(Model.withoutDismissed(planned.entries, root.dismissed), root.maxItems, root.keepDays, Date.now())
    archiveView.setText(Model.serializeArchive(root.entries))
  }

  // One-time, read-only import of the retired third-party center's archive:
  // entries are copied, never moved; that directory is never written to.
  // Already-discarded keys stay discarded.
  function importLegacy(raw) {
    var rows = Model.withoutDismissed(Model.parseEntryLines(raw), root.dismissed)
    if (rows.length === 0) {
      markImported()
      return
    }
    var merged = Model.mergeEntries(root.entries, rows, root.dismissed)
    var first = Model.planImageCopies(merged, root.omarchyImagesDir, root.ownImagesDir)
    var second = Model.planImageCopies(first.entries, root.legacyImagesDir, root.ownImagesDir)
    runCopies(first.copies.concat(second.copies))
    root.entries = Model.trimEntries(second.entries, root.maxItems, root.keepDays, Date.now())
    archiveView.setText(Model.serializeArchive(root.entries))
    markImported()
  }

  function markImported() {
    markImportedProc.command = ["bash", "-c", "mkdir -p \"$1\" && touch \"$1/imported\"", "--", root.storeDir]
    markImportedProc.running = true
  }

  function runCopies(copies) {
    var jobs = (copies || []).slice(0, 50)
    if (jobs.length === 0) return
    var command = ["bash", "-c",
      "mkdir -p \"$1\" || exit 0\nshift\n" +
      "while (( $# >= 2 )); do cp -f -- \"$1\" \"$2\" 2>/dev/null || true; shift 2; done",
      "--", root.ownImagesDir]
    for (var i = 0; i < jobs.length; i++) command.push(jobs[i].from, jobs[i].to)
    copyProc.command = command
    copyProc.running = true
  }

  function seedEntries(count) {
    var rows = Model.makeSeedEntries(count, Date.now())
    if (rows.length === 0) return "none"
    var visible = Model.withoutDismissed(rows, root.dismissed)
    root.entries = Model.trimEntries(Model.mergeEntries(root.entries, visible, root.dismissed), root.maxItems, root.keepDays, Date.now())
    archiveView.setText(Model.serializeArchive(root.entries))
    return "seeded " + rows.length
  }

  Component.onCompleted: ingestNow()

  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: root.ingestNow()
  }

  FileView {
    id: archiveView
    path: root.archivePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var rows = Model.withoutDismissed(Model.parseEntryLines(text()), root.dismissed)
      root.entries = Model.trimEntries(rows, root.maxItems, root.keepDays, Date.now())
    }
    onLoadFailed: {
      // First run: no archive yet. The legacy import and the poll below fill
      // entries; either way the panel renders an honest empty state, never a
      // spinner.
    }
  }

  // Tombstone store: union what is on disk with the in-memory map (our own
  // appends may not have flushed yet) so concurrent instances converge instead
  // of overwriting each other. Matching in-memory entries are dropped without
  // rewriting the archive — the dismissing instance already did — so instances
  // never ping-pong writes at each other. The file is rewritten only when the
  // bound actually evicts something, which keeps it from growing without limit.
  FileView {
    id: dismissedView
    path: root.dismissedPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var loaded = Model.parseDismissedLines(text())
      var union = Model.mergeDismissed(root.dismissed, loaded)
      var trimmed = Model.trimDismissed(union, root.dismissedCap(), root.keepDays, Date.now())
      root.dismissed = trimmed
      var kept = Model.withoutDismissed(root.entries, trimmed)
      if (kept.length !== root.entries.length) root.entries = kept
      if (Object.keys(trimmed).length < Object.keys(loaded).length) {
        dismissedView.setText(Model.serializeDismissed(trimmed))
      }
    }
    onLoadFailed: {
      // No tombstone file yet: nothing discarded anywhere, keep the map as is.
    }
  }

  FileView {
    id: seenView
    path: root.seenPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var value = Number(String(text()).trim())
      root.seenMs = isFinite(value) ? value : 0
    }
    onLoadFailed: root.seenMs = 0
  }

  FileView {
    id: importMarkerView
    path: root.importMarkerPath
    watchChanges: false
    printErrors: false
    onLoadFailed: {
      // No marker: this store never imported. A missing legacy archive reads
      // back empty and importLegacy() just records the marker.
      importProc.command = ["bash", "-c", "head -c 8388608 -- \"$1\" 2>/dev/null || true", "--", root.legacyArchivePath]
      importProc.running = true
    }
  }

  FileView {
    id: dndView
    path: root.dndSettingsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.dndFileState = Model.parseDndSettings(text())
    onLoadFailed: root.dndFileState = false
  }

  Process {
    id: ingestProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ingestOmarchy(text)
    }
  }

  Process {
    id: importProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.importLegacy(text)
    }
  }

  Process {
    id: copyProc
    running: false
  }

  Process {
    id: markImportedProc
    running: false
  }

  Process {
    id: dismissAppendProc
    running: false
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "orbital.notifications"

    function state(): string {
      return JSON.stringify(Model.stateSummary(root.entries, root.seenMs))
    }
    function clear(): string {
      root.clearAll()
      return "cleared"
    }
    function dismiss(key: string): string {
      root.dismissEntry(key)
      return "ok"
    }
    function reload(): string {
      root.broadcast("ingestNow")
      return "reloading"
    }
    function seed(count: string): string {
      return root.seedEntries(Number(count || 0))
    }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    // Icon-only button: the label Text is empty, so without a fixed width the
    // slot would shrink to the margins and the bell would bleed into its
    // neighbours (WidgetButton sizes off the label, not its children).
    fixedWidth: 32
    horizontalMargin: 7
    tooltipText: root.unread > 0 ? tr("Notifications") + " (" + root.unread + ")" : tr("Notifications")
    onPressed: function() { root.togglePanel() }

    OrbitalUi.OrbitalTokens { id: tokens }

    OrbitalUi.OrbitalIcon {
      id: bell
      anchors.centerIn: parent
      size: 18
      name: "notifications-bell-symbolic"
      tint: root.bar ? root.bar.barForeground : tokens.text
      opacity: root.dnd ? 0.55 : 1.0
    }

    // Unread badge: a dot that says "some", or a count that says "how many".
    // "None" leaves the bell alone.
    Rectangle {
      id: dotBadge
      visible: root.badgeMode === "Dot" && root.unread > 0
      width: 8
      height: 8
      radius: width / 2
      color: tokens.accent
      anchors.top: parent.top
      anchors.topMargin: Math.max(0, (parent.height - bell.size) / 2 - 1)
      anchors.right: parent.right
      anchors.rightMargin: Math.max(0, (parent.width - bell.size) / 2 - 1)
    }

    Rectangle {
      id: countBadge
      visible: root.badgeMode === "Count" && root.unread > 0
      width: Math.max(height, countLabel.implicitWidth + 8)
      height: 16
      radius: height / 2
      color: tokens.accent
      anchors.top: parent.top
      anchors.topMargin: Math.max(0, (parent.height - bell.size) / 2 - 4)
      anchors.right: parent.right
      anchors.rightMargin: 1

      Text {
        id: countLabel
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.unread > 99 ? "99+" : String(root.unread)
        color: tokens.text
        font.family: tokens.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }
}
