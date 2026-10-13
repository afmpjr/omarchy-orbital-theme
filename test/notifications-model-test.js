// Node unit tests for plugins/orbital.notifications/NotificationsModel.js.
// Run: bash scripts/test-notifications-model.sh (needs only `node`).
var assert = require("assert")
var path = require("path")
var Model = require(path.join(__dirname, "..", "plugins", "orbital.notifications", "NotificationsModel.js"))

var passed = 0
function check(name, fn) {
  fn()
  passed++
  console.log("ok - " + name)
}

// --- normalizeEntry folds all three on-disk shapes into one ---
check("normalize omarchy history shape", function () {
  var e = Model.normalizeEntry({ id: 3, originalId: 3, app: "", appIcon: "com.mitchellh.ghostty",
    summary: "Claude Code", body: "waiting", image: "", glyph: "", execArgv: "",
    urgency: 1, expireTimeout: 0, timestamp: 1791843067032 })
  assert.strictEqual(e.key, "1791843067032-3")
  assert.strictEqual(e.summary, "Claude Code")
  assert.strictEqual(e.execArgv, undefined)
  assert.strictEqual(e.expireTimeout, undefined)
})

check("normalize third-party archive shape keeps preview as image", function () {
  var e = Model.normalizeEntry({ key: "1791231760645-1", app: "", appIcon: "x",
    summary: "s", body: "b", image: "", preview: "file:///tmp/p.png", file: "",
    glyph: "", urgency: 1, timestamp: 1791231760645 })
  assert.strictEqual(e.key, "1791231760645-1")
  assert.strictEqual(e.image, "file:///tmp/p.png")
})

check("normalize drops malformed timestamps and urgencies", function () {
  var e = Model.normalizeEntry({ summary: "x", timestamp: "junk", urgency: "high" })
  assert.strictEqual(e.timestamp, 0)
  assert.strictEqual(e.urgency, 1)
})

// --- image/appIcon sanitizing: only local paths and theme names survive ---
check("normalize drops remote image/appIcon URLs", function () {
  var e = Model.normalizeEntry({ summary: "x", timestamp: 1, originalId: 1,
    appIcon: "https://evil.example/t.png", image: "http://evil.example/p.png" })
  assert.strictEqual(e.appIcon, "")
  assert.strictEqual(e.image, "")
  e = Model.normalizeEntry({ summary: "x", timestamp: 1, originalId: 1,
    appIcon: "data:image/png;base64,AAA", image: "javascript:alert(1)" })
  assert.strictEqual(e.appIcon, "")
  assert.strictEqual(e.image, "")
})

check("normalize drops remote preview fallback too", function () {
  var e = Model.normalizeEntry({ summary: "x", timestamp: 1, originalId: 1,
    image: "", preview: "https://evil.example/p.png" })
  assert.strictEqual(e.image, "")
})

check("normalize keeps local paths, file URLs and theme icon names", function () {
  var e = Model.normalizeEntry({ summary: "x", timestamp: 1, originalId: 1,
    appIcon: "com.mitchellh.ghostty", image: "file:///tmp/p.png" })
  assert.strictEqual(e.appIcon, "com.mitchellh.ghostty")
  assert.strictEqual(e.image, "file:///tmp/p.png")
  e = Model.normalizeEntry({ summary: "x", timestamp: 1, originalId: 1,
    appIcon: "/usr/share/icons/app.png", image: "/tmp/p.png", preview: "notifications-bell-symbolic" })
  assert.strictEqual(e.appIcon, "/usr/share/icons/app.png")
  assert.strictEqual(e.image, "/tmp/p.png")
  assert.strictEqual(Model.sanitizeImageRef("notifications-bell-symbolic"), "notifications-bell-symbolic")
})

check("normalize drops relative paths and odd icon names", function () {
  assert.strictEqual(Model.sanitizeImageRef("images/p.png"), "")
  assert.strictEqual(Model.sanitizeImageRef("../etc/passwd"), "")
  assert.strictEqual(Model.sanitizeImageRef("file://relative/p.png"), "")
  assert.strictEqual(Model.sanitizeImageRef("my icon"), "")
  assert.strictEqual(Model.sanitizeImageRef("image://dead"), "")
  assert.strictEqual(Model.sanitizeImageRef(""), "")
})

// --- parseEntryLines skips torn lines, sorts newest first ---
check("parse skips torn lines", function () {
  var text = '{"summary":"old","timestamp":100,"originalId":1}\n{"summary":\n{"summary":"new","timestamp":300,"originalId":2}\n'
  var rows = Model.parseEntryLines(text)
  assert.strictEqual(rows.length, 2)
  assert.strictEqual(rows[0].summary, "new")
  assert.strictEqual(rows[1].summary, "old")
})

// --- mergeEntries dedupes by key across re-reads and racers ---
check("merge dedupes by key, newest first", function () {
  var a = Model.normalizeEntry({ summary: "a", timestamp: 100, originalId: 1 })
  var b = Model.normalizeEntry({ summary: "b", timestamp: 200, originalId: 2 })
  var out = Model.mergeEntries([a], [a, b])
  assert.strictEqual(out.length, 2)
  assert.strictEqual(out[0].summary, "b")
})

// --- trimEntries: whichever of age/count caps hits first wins ---
check("trim keeps newest 2 of 3", function () {
  var rows = [300, 200, 100].map(function (t, i) {
    return Model.normalizeEntry({ summary: "s" + i, timestamp: t, originalId: i })
  })
  var out = Model.trimEntries(rows, 2, 365, 1000000)
  assert.strictEqual(out.length, 2)
  assert.strictEqual(out[0].timestamp, 300)
})

check("trim drops entries older than keepDays", function () {
  var now = 30 * 24 * 3600 * 1000 + 1000000
  var rows = [
    Model.normalizeEntry({ summary: "fresh", timestamp: now - 1000, originalId: 1 }),
    Model.normalizeEntry({ summary: "stale", timestamp: now - 40 * 24 * 3600 * 1000, originalId: 2 })
  ]
  var out = Model.trimEntries(rows, 1000, 30, now)
  assert.strictEqual(out.length, 1)
  assert.strictEqual(out[0].summary, "fresh")
})

// --- unread / filter / relative time ---
check("unread counts entries newer than seen", function () {
  var rows = [100, 200, 300].map(function (t, i) {
    return Model.normalizeEntry({ summary: "s", timestamp: t, originalId: i })
  })
  assert.strictEqual(Model.unreadCount(rows, 150), 2)
  assert.strictEqual(Model.unreadCount(rows, 300), 0)
  assert.strictEqual(Model.unreadCount([], 0), 0)
})

check("filter matches app/summary/body case-insensitively", function () {
  var rows = [
    Model.normalizeEntry({ app: "Chrome", summary: "question", body: "", timestamp: 1, originalId: 1 }),
    Model.normalizeEntry({ app: "Ghostty", summary: "waiting", body: "", timestamp: 2, originalId: 2 })
  ]
  assert.strictEqual(Model.filterEntries(rows, "chrom").length, 1)
  assert.strictEqual(Model.filterEntries(rows, "").length, 2)
  assert.strictEqual(Model.filterEntries(rows, "zzz").length, 0)
})

check("relative parts across the unit ladder", function () {
  var now = 1000000000000
  assert.deepStrictEqual(Model.relativeParts(now - 10 * 1000, now), { kind: "now" })
  assert.deepStrictEqual(Model.relativeParts(now - 60 * 1000, now), { kind: "ago", amount: 1, unit: "minute" })
  assert.deepStrictEqual(Model.relativeParts(now - 5 * 60 * 1000, now), { kind: "ago", amount: 5, unit: "minutes" })
  assert.deepStrictEqual(Model.relativeParts(now - 2 * 3600 * 1000, now), { kind: "ago", amount: 2, unit: "hours" })
  assert.deepStrictEqual(Model.relativeParts(now - 3 * 24 * 3600 * 1000, now), { kind: "ago", amount: 3, unit: "days" })
  assert.deepStrictEqual(Model.relativeParts(now - 14 * 24 * 3600 * 1000, now), { kind: "ago", amount: 2, unit: "weeks" })
  assert.deepStrictEqual(Model.relativeParts(now - 60 * 24 * 3600 * 1000, now), { kind: "date" })
  assert.deepStrictEqual(Model.relativeParts(now + 5000, now), { kind: "now" })
})

// --- archive round-trip + dnd fallback parse ---
check("serialize round-trips through parse", function () {
  var rows = [
    Model.normalizeEntry({ app: "a", summary: "one", body: "x\ny", timestamp: 5, originalId: 1 }),
    Model.normalizeEntry({ app: "b", summary: "two", timestamp: 6, originalId: 2 })
  ]
  var back = Model.parseEntryLines(Model.serializeArchive(rows))
  assert.strictEqual(back.length, 2)
  assert.strictEqual(back[0].summary, "two")
  assert.strictEqual(back[1].body, "x\ny")
})

check("dnd settings parse", function () {
  assert.strictEqual(Model.parseDndSettings('{"version":3,"dnd":true}'), true)
  assert.strictEqual(Model.parseDndSettings('{"version":3,"dnd":false}'), false)
  assert.strictEqual(Model.parseDndSettings(""), false)
  assert.strictEqual(Model.parseDndSettings("torn {"), false)
})

// --- image copy planning touches only omarchy-owned file paths ---
check("image copies planned only for omarchy files", function () {
  var rows = [
    Model.normalizeEntry({ summary: "a", timestamp: 1, originalId: 1,
      image: "file:///home/u/.local/state/omarchy/notifications/images/1-1-image" }),
    Model.normalizeEntry({ summary: "b", timestamp: 2, originalId: 2,
      appIcon: "com.mitchellh.ghostty", image: "image://dead" })
  ]
  var plan = Model.planImageCopies(rows, "/home/u/.local/state/omarchy/notifications/images/", "/home/u/.local/state/omarchy/orbital-notifications/images/")
  assert.strictEqual(plan.copies.length, 1)
  assert.strictEqual(plan.copies[0].from, "/home/u/.local/state/omarchy/notifications/images/1-1-image")
  assert.strictEqual(plan.entries[0].image, "file:///home/u/.local/state/omarchy/orbital-notifications/images/1-1-image")
  assert.strictEqual(plan.entries[1].appIcon, "com.mitchellh.ghostty")
  // Non-local artwork never survives normalizeEntry, so there is nothing left
  // here for the panel to fetch remotely.
  assert.strictEqual(plan.entries[1].image, "")
})

// --- dismissed tombstones: discards persist across polls and restarts ---
check("dismissed round-trips through parse/serialize", function () {
  var map = Model.addDismissed({}, ["100-1", "200-2"], 5000)
  var back = Model.parseDismissedLines(Model.serializeDismissed(map))
  assert.deepStrictEqual(back, { "100-1": 5000, "200-2": 5000 })
  assert.deepStrictEqual(Model.parseDismissedLines("torn {\n\n"), {})
  assert.deepStrictEqual(Model.parseDismissedLines('{"nope":1}\n{"key":"","at":9}\n'), {})
})

check("dismissedLines formats one JSON line per key", function () {
  var lines = Model.dismissedLines(["100-1", "", "200-2"], 7777)
  assert.strictEqual(lines.length, 2)
  assert.deepStrictEqual(JSON.parse(lines[0]), { key: "100-1", at: 7777 })
  assert.strictEqual(Model.dismissedLines([], 1).length, 0)
})

check("merge excludes dismissed keys, old callers unaffected", function () {
  var a = Model.normalizeEntry({ summary: "a", timestamp: 100, originalId: 1 })
  var b = Model.normalizeEntry({ summary: "b", timestamp: 200, originalId: 2 })
  var out = Model.mergeEntries([a], [a, b], { "100-1": 5000 })
  assert.strictEqual(out.length, 1)
  assert.strictEqual(out[0].summary, "b")
  assert.strictEqual(Model.mergeEntries([a], [a, b]).length, 2)
})

check("withoutDismissed drops discarded entries", function () {
  var rows = [100, 200].map(function (t, i) {
    return Model.normalizeEntry({ summary: "s" + i, timestamp: t, originalId: i + 1 })
  })
  assert.strictEqual(Model.withoutDismissed(rows, { "100-1": 1 }).length, 1)
  assert.strictEqual(Model.withoutDismissed(rows, null).length, 2)
})

check("mergeDismissed unions, newest discard wins", function () {
  assert.deepStrictEqual(Model.mergeDismissed({ "1-1": 10 }, { "1-1": 30, "2-2": 5 }), { "1-1": 30, "2-2": 5 })
  assert.deepStrictEqual(Model.mergeDismissed(null, { "1-1": 1 }), { "1-1": 1 })
})

check("trimDismissed expires by age and caps by count", function () {
  var now = 30 * 24 * 3600 * 1000 + 1000000
  var freshKey = String(now - 5000) + "-3" // at 0: age falls back to the key time
  var map = {
    "100-1": now - 1000, // fresh, kept
    "200-2": now - 40 * 24 * 3600 * 1000, // older than keepDays, dropped
  }
  map[freshKey] = 0 // unknown discard time, fresh key time: kept by the age pass
  map["legacy-no-time"] = 0 // no parseable time at all: kept by the age pass
  var out = Model.trimDismissed(map, 1000, 30, now)
  assert.ok(!("200-2" in out))
  assert.ok("100-1" in out)
  assert.ok(freshKey in out)
  assert.ok("legacy-no-time" in out)
  // Ancient key time with no discard time is still older than keepDays.
  out = Model.trimDismissed({ "300-3": 0 }, 1000, 30, now)
  assert.ok(!("300-3" in out))
  out = Model.trimDismissed({ "1-1": 1, "2-2": 2, "3-3": 3 }, 2, 365, now)
  assert.strictEqual(Object.keys(out).length, 2)
  assert.ok(!("1-1" in out))
  assert.ok("3-3" in out)
})

check("dismissed key re-ingested from disk stays gone", function () {
  var raw = JSON.stringify({ summary: "ping", timestamp: 100, originalId: 1 })
  var archived = Model.parseEntryLines(raw)
  assert.strictEqual(archived.length, 1)
  // Dismiss: drop from entries, record the tombstone.
  var dismissed = Model.addDismissed({}, [archived[0].key], 5000)
  var entries = Model.withoutDismissed(archived, dismissed)
  assert.strictEqual(entries.length, 0)
  // Next 3 s poll re-reads the same omarchy file: the key must not come back.
  var again = Model.withoutDismissed(Model.parseEntryLines(raw), dismissed)
  var merged = Model.mergeEntries(entries, again, dismissed)
  assert.strictEqual(merged.length, 0)
})

// --- seed entries are deterministic and ordered ---
check("seed entries deterministic", function () {
  var rows = Model.makeSeedEntries(3, 1000000)
  assert.strictEqual(rows.length, 3)
  assert.strictEqual(rows[0].app, "orbital-seed")
  assert.ok(rows[0].timestamp > rows[1].timestamp)
  assert.strictEqual(Model.makeSeedEntries(0, 1).length, 0)
  assert.strictEqual(Model.makeSeedEntries(99999, 1).length, 5000)
})

// --- state summary for the IPC verb ---
check("state summary", function () {
  var rows = [
    Model.normalizeEntry({ summary: "newest", timestamp: 200, originalId: 1 }),
    Model.normalizeEntry({ summary: "older", timestamp: 100, originalId: 2 })
  ]
  assert.deepStrictEqual(Model.stateSummary(rows, 150), { total: 2, unread: 1, newest: "newest" })
  assert.deepStrictEqual(Model.stateSummary([], 0), { total: 0, unread: 0, newest: "" })
  var read = Model.setRead({}, ["200-1"], true, 5000)
  assert.deepStrictEqual(Model.stateSummary(rows, read), { total: 2, unread: 1, newest: "newest" })
})

// --- per-notification read state: absent keys are unread ---
check("isRead defaults unread, setRead marks both ways", function () {
  assert.strictEqual(Model.isRead({}, "100-1"), false)
  assert.strictEqual(Model.isRead(null, "100-1"), false)
  var read = Model.setRead({}, ["100-1"], true, 5000)
  assert.strictEqual(Model.isRead(read, "100-1"), true)
  assert.strictEqual(Model.isRead(read, "200-2"), false)
  read = Model.setRead(read, ["100-1"], false, 6000)
  assert.strictEqual(Model.isRead(read, "100-1"), false)
})

check("read round-trips through parse/serialize", function () {
  var map = Model.setRead(Model.setRead({}, ["100-1"], true, 5000), ["200-2"], false, 6000)
  var back = Model.parseReadLines(Model.serializeRead(map))
  assert.deepStrictEqual(back, map)
  assert.deepStrictEqual(Model.parseReadLines("torn {\n\n"), {})
  assert.deepStrictEqual(Model.parseReadLines('{"nope":1}\n{"key":"","read":true,"at":9}\n'), {})
})

check("readLines formats one JSON line per key", function () {
  var lines = Model.readLines(["100-1", "", "200-2"], true, 7777)
  assert.strictEqual(lines.length, 2)
  assert.deepStrictEqual(JSON.parse(lines[0]), { key: "100-1", read: true, at: 7777 })
  lines = Model.readLines("100-1", false, 7777)
  assert.deepStrictEqual(JSON.parse(lines[0]), { key: "100-1", read: false, at: 7777 })
  assert.strictEqual(Model.readLines([], true, 1).length, 0)
})

check("unreadCount over the read map", function () {
  var rows = [100, 200, 300].map(function (t, i) {
    return Model.normalizeEntry({ summary: "s", timestamp: t, originalId: i })
  })
  assert.strictEqual(Model.unreadCount(rows, {}), 3)
  var read = Model.setRead({}, [rows[0].key, rows[2].key], true, 5000)
  assert.strictEqual(Model.unreadCount(rows, read), 1)
  read = Model.setRead(read, [rows[0].key], false, 6000)
  assert.strictEqual(Model.unreadCount(rows, read), 2)
  // Marking every row read clears the bell.
  var all = Model.setRead({}, rows.map(function (e) { return e.key }), true, 7000)
  assert.strictEqual(Model.unreadCount(rows, all), 0)
  // Numeric legacy `seen` still reads honestly.
  assert.strictEqual(Model.unreadCount(rows, 150), 2)
})

check("unreadEntries filters to unmarked rows", function () {
  var rows = [100, 200].map(function (t, i) {
    return Model.normalizeEntry({ summary: "s" + i, timestamp: t, originalId: i + 1 })
  })
  var read = Model.setRead({}, [rows[0].key], true, 5000)
  var out = Model.unreadEntries(rows, read)
  assert.strictEqual(out.length, 1)
  assert.strictEqual(out[0].key, rows[1].key)
  assert.strictEqual(Model.unreadEntries(rows, {}).length, 2)
})

check("migration: entries at/below seen become read", function () {
  var rows = [100, 200, 300].map(function (t, i) {
    return Model.normalizeEntry({ summary: "s", timestamp: t, originalId: i })
  })
  var migrated = Model.migrateSeenToRead(rows, 200, 9000)
  assert.strictEqual(Model.isRead(migrated, rows[0].key), true)
  assert.strictEqual(Model.isRead(migrated, rows[1].key), true)
  assert.strictEqual(Model.isRead(migrated, rows[2].key), false)
  assert.strictEqual(Model.unreadCount(rows, migrated), 1)
  assert.deepStrictEqual(Model.migrateSeenToRead(rows, 0, 9000), {})
  assert.deepStrictEqual(Model.migrateSeenToRead([], 200, 9000), {})
})

check("legacy import arrives fully read", function () {
  var rows = [100, 200].map(function (t, i) {
    return Model.normalizeEntry({ summary: "old" + i, timestamp: t, originalId: i + 1 })
  })
  var map = Model.legacyReadMap(rows, 9000)
  assert.strictEqual(Model.unreadCount(rows, map), 0)
  // A foreign `read` flag on disk never sneaks into the canonical entry: the
  // read state lives in its own file, not in the archive.
  var e = Model.normalizeEntry({ summary: "x", timestamp: 1, originalId: 1, read: true })
  assert.strictEqual(e.read, undefined)
})

check("mergeRead: newest marking wins per key", function () {
  var a = Model.setRead({}, ["1-1"], true, 1000)
  var b = Model.setRead({}, ["1-1"], false, 2000)
  assert.strictEqual(Model.isRead(Model.mergeRead(a, b), "1-1"), false)
  assert.strictEqual(Model.isRead(Model.mergeRead(b, a), "1-1"), false)
  var c = Model.setRead({}, ["1-1"], false, 500)
  assert.strictEqual(Model.isRead(Model.mergeRead(a, c), "1-1"), true)
  assert.deepStrictEqual(Model.mergeRead(null, a), a)
})

check("two instances converge over appended read lines", function () {
  // Instance A marks one row read, instance B another; each appends its own
  // lines and both reload the shared file: union, no clobbering.
  var linesA = Model.readLines(["100-1"], true, 5000)
  var linesB = Model.readLines(["200-2"], true, 6000)
  var file = linesA.concat(linesB).join("\n") + "\n"
  var converged = Model.mergeRead(Model.parseReadLines(linesA.join("\n") + "\n"), Model.parseReadLines(file))
  assert.strictEqual(Model.isRead(converged, "100-1"), true)
  assert.strictEqual(Model.isRead(converged, "200-2"), true)
  // A later unread marking on A wins over its own earlier read.
  var later = Model.readLines(["100-1"], false, 7000)
  converged = Model.mergeRead(converged, Model.parseReadLines(later.join("\n") + "\n"))
  assert.strictEqual(Model.isRead(converged, "100-1"), false)
  assert.strictEqual(Model.isRead(converged, "200-2"), true)
})

check("trimRead expires by age and caps by count", function () {
  var now = 30 * 24 * 3600 * 1000 + 1000000
  var freshKey = String(now - 5000) + "-3"
  var map = Model.setRead({}, ["100-1", freshKey, "legacy-no-time"], true, now - 1000)
  map["200-2"] = { read: true, at: now - 40 * 24 * 3600 * 1000 } // older than keepDays
  var out = Model.trimRead(map, 1000, 30, now)
  assert.ok(!("200-2" in out))
  assert.ok("100-1" in out)
  assert.ok(freshKey in out)
  assert.ok("legacy-no-time" in out)
  out = Model.trimRead({ "300-3": { read: true, at: 0 } }, 1000, 30, now)
  assert.ok(!("300-3" in out))
  out = Model.trimRead(Model.setRead({}, ["1-1", "2-2", "3-3"], true, now), 2, 365, now)
  assert.strictEqual(Object.keys(out).length, 2)
})

// --- volume: 5000 synthetic entries parse+merge+trim in well under a second ---
check("volume: 5000 entries without stalling", function () {
  var lines = []
  for (var i = 0; i < 5000; i++) {
    lines.push(JSON.stringify({ app: "load", summary: "entry " + i, body: "x".repeat(200),
      timestamp: 1700000000000 + i, originalId: i }))
  }
  var started = Date.now()
  var rows = Model.parseEntryLines(lines.join("\n"))
  rows = Model.mergeEntries([], rows)
  rows = Model.trimEntries(rows, 1000, 30, 1700000000000 + 5000)
  var elapsed = Date.now() - started
  assert.strictEqual(rows.length, 1000)
  assert.ok(elapsed < 5000, "took " + elapsed + "ms")
  console.log("    (5000-entry ingest+trim took " + elapsed + "ms)")
})

console.log("ok - " + passed + " notification model checks passed")
