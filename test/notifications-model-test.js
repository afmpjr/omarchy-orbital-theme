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
  assert.strictEqual(plan.entries[1].image, "image://dead")
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
