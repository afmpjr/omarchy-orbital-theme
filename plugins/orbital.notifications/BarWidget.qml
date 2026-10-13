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
  readonly property string readPath: storeDir + "read.jsonl"
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
  // Read/unread state per notification ({ key: { read, at } }): absent keys are
  // unread, so new arrivals light the bell with no write. Persisted
  // append-only in read.jsonl and converged across the per-monitor instances
  // through the watcher below (newest marking wins), exactly like the
  // dismissed tombstones. Opening the panel marks nothing.
  property var read: ({})
  // Panel filter memory: the Todas/Não lidas choice survives close/reopen
  // within the session (the widget outlives its panel).
  property bool unreadOnly: false
  // Legacy global timestamp, read once for the seen-to-read migration (entries
  // at or below it become read). Never written anymore.
  property double seenMs: 0
  readonly property int unread: Model.unreadCount(entries, read)

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

  // Marking helpers: every marking appends its lines to read.jsonl (queued, so
  // rapid clicks never lose a write) and updates the in-memory map at once so
  // the bell answers immediately, before the watcher round-trips.
  function markRead(key) {
    var needle = String(key || "")
    if (!needle || Model.isRead(root.read, needle)) return
    var now = Date.now()
    root.read = Model.trimRead(Model.setRead(root.read, [needle], true, now), readCap(), root.keepDays, now)
    enqueueAppend(root.readPath, Model.readLines([needle], true, now))
  }

  function markUnread(key) {
    var needle = String(key || "")
    if (!needle || !Model.isRead(root.read, needle)) return
    var now = Date.now()
    root.read = Model.trimRead(Model.setRead(root.read, [needle], false, now), readCap(), root.keepDays, now)
    enqueueAppend(root.readPath, Model.readLines([needle], false, now))
  }

  function markAllRead() {
    var keys = []
    for (var i = 0; i < root.entries.length; i++) {
      if (!Model.isRead(root.read, root.entries[i].key)) keys.push(root.entries[i].key)
    }
    if (keys.length === 0) return
    var now = Date.now()
    root.read = Model.trimRead(Model.setRead(root.read, keys, true, now), readCap(), root.keepDays, now)
    enqueueAppend(root.readPath, Model.readLines(keys, true, now))
  }

  // Seen-to-read migration for entries that predate the per-notification
  // state: anything at or below the legacy `seen` timestamp was visible when
  // the panel last opened, so it counts as read. Idempotent (keys already
  // marked are skipped), so every archive/seen reload can call it safely.
  function applySeenMigration() {
    if (!(root.seenMs > 0) || root.entries.length === 0) return
    var now = Date.now()
    var migrated = Model.migrateSeenToRead(root.entries, root.seenMs, now)
    var fresh = []
    for (var key in migrated) {
      if (!Model.isRead(root.read, key)) fresh.push(key)
    }
    if (fresh.length === 0) return
    root.read = Model.trimRead(Model.mergeRead(root.read, migrated), readCap(), root.keepDays, now)
    enqueueAppend(root.readPath, Model.readLines(fresh, true, now))
  }

  function clearAll() {
    var keys = root.entries.map(function (e) { return e.key })
    if (keys.length > 0) {
      root.dismissed = Model.trimDismissed(Model.addDismissed(root.dismissed, keys, Date.now()), dismissedCap(), root.keepDays, Date.now())
      appendDismissed(keys)
    }
    root.entries = []
    writeArchive()
  }

  function dismissEntry(key) {
    var needle = String(key || "")
    if (!needle) return
    root.dismissed = Model.trimDismissed(Model.addDismissed(root.dismissed, [needle], Date.now()), dismissedCap(), root.keepDays, Date.now())
    appendDismissed([needle])
    root.entries = root.entries.filter(function (e) { return String(e.key || "") !== needle })
    writeArchive()
  }

  // Tombstones and read markings stay bounded: same age window as the archive,
  // count capped at (at least) 1000 so every key the archive could still hold
  // stays covered.
  function dismissedCap() {
    return Math.max(1000, root.maxItems)
  }

  function readCap() {
    return Math.max(1000, root.maxItems)
  }

  // Single append queue for every append-only store (dismissed.jsonl,
  // read.jsonl). The old code parked each write on one shared Process: two
  // discards landing milliseconds apart overwrote the pending command and one
  // append never reached the disk. Jobs queue here and pump one at a time;
  // consecutive jobs for the same file group into one shell call, so a burst
  // of per-row markings costs a single append. Values travel as argv, never
  // interpolated into the shell script.
  property var appendQueue: []

  function enqueueAppend(path, lines) {
    var fresh = (lines || []).filter(function (l) { return l })
    if (fresh.length === 0 || !path) return
    var queue = root.appendQueue.slice()
    var tail = queue.length > 0 ? queue[queue.length - 1] : null
    if (tail && tail.file === path && tail.lines.length + fresh.length <= 500) {
      tail.lines = tail.lines.concat(fresh)
    } else {
      queue.push({ file: String(path), lines: fresh })
    }
    root.appendQueue = queue
    pumpAppendQueue()
  }

  function pumpAppendQueue() {
    if (fileAppendProc.running || root.appendQueue.length === 0) return
    var job = root.appendQueue[0]
    root.appendQueue = root.appendQueue.slice(1)
    var command = ["bash", "-c",
      "f=\"$1\"; shift\nmkdir -p \"$(dirname \"$f\")\"\nfor l in \"$@\"; do printf '%s\\n' \"$l\" >> \"$f\"; done",
      "--", job.file]
    for (var i = 0; i < job.lines.length; i++) command.push(job.lines[i])
    fileAppendProc.command = command
    fileAppendProc.running = true
  }

  // Append-only so two per-monitor instances discarding at the same moment
  // never clobber each other (a full rewrite would last-writer-wins).
  function appendDismissed(keys) {
    enqueueAppend(root.dismissedPath, Model.dismissedLines(keys, Date.now()))
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
    var now = Date.now()
    // Fresh arrivals are unread, except pre-migration ones at or below the
    // legacy `seen` timestamp, which count as already seen.
    var migrated = Model.migrateSeenToRead(fresh, root.seenMs, now)
    if (Object.keys(migrated).length > 0) {
      root.read = Model.trimRead(Model.mergeRead(root.read, migrated), readCap(), root.keepDays, now)
      enqueueAppend(root.readPath, Model.readLines(Object.keys(migrated), true, now))
    }
    var merged = Model.mergeEntries(root.entries, fresh, root.dismissed)
    var planned = Model.planImageCopies(merged, root.omarchyImagesDir, root.ownImagesDir)
    runCopies(planned.copies)
    root.entries = Model.trimEntries(Model.withoutDismissed(planned.entries, root.dismissed), root.maxItems, root.keepDays, Date.now())
    archiveView.setText(Model.serializeArchive(root.entries))
  }

  // One-time, read-only import of the retired third-party center's archive:
  // entries are copied, never moved; that directory is never written to.
  // Already-discarded keys stay discarded. Every imported entry arrives READ,
  // so the first run never lights the bell over ~950 old rows.
  function importLegacy(raw) {
    var rows = Model.withoutDismissed(Model.parseEntryLines(raw), root.dismissed)
    if (rows.length === 0) {
      markImported()
      return
    }
    var now = Date.now()
    root.read = Model.trimRead(Model.mergeRead(root.read, Model.legacyReadMap(rows, now)), readCap(), root.keepDays, now)
    enqueueAppend(root.readPath, Model.readLines(rows.map(function (e) { return e.key }), true, now))
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
    // Synthetic entries arrive unread (no read markings), like any arrival.
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
      root.applySeenMigration()
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

  // Read-marking store: union what is on disk with the in-memory map (our own
  // appends may not have flushed yet) so concurrent instances converge instead
  // of overwriting each other. Newest marking wins per key, so a read here
  // and an unread there resolve deterministically everywhere. The file is
  // rewritten only when the bound actually evicts something.
  FileView {
    id: readView
    path: root.readPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var loaded = Model.parseReadLines(text())
      var union = Model.mergeRead(root.read, loaded)
      var trimmed = Model.trimRead(union, root.readCap(), root.keepDays, Date.now())
      root.read = trimmed
      if (Object.keys(trimmed).length < Object.keys(loaded).length) {
        readView.setText(Model.serializeRead(trimmed))
      }
    }
    onLoadFailed: {
      // No read file yet: everything unmarked is unread, keep the map as is.
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
      root.applySeenMigration()
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
    id: fileAppendProc
    running: false
    onRunningChanged: {
      if (!fileAppendProc.running) root.pumpAppendQueue()
    }
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
      return JSON.stringify(Model.stateSummary(root.entries, root.read))
    }
    function clear(): string {
      root.clearAll()
      return "cleared"
    }
    function dismiss(key: string): string {
      root.dismissEntry(key)
      return "ok"
    }
    function markRead(key: string): string {
      root.markRead(key)
      return "ok"
    }
    function markUnread(key: string): string {
      root.markUnread(key)
      return "ok"
    }
    function markAllRead(): string {
      root.markAllRead()
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
