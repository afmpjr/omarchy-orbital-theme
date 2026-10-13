// History math for the Orbital notification center widget, kept Qt-free so it
// can be unit tested under node (scripts/test-notifications-model.sh).
//
// The widget keeps its own archive (one compact JSON object per line, newest
// first on read) under ~/.local/state/omarchy/orbital-notifications/. Entries
// arrive from three shapes that all describe the same notification:
//   - omarchy history files (Service.qml persistence: id, originalId, app,
//     appIcon, summary, body, image, glyph, execArgv, urgency, expireTimeout,
//     timestamp)
//   - the retired third-party center's archive.jsonl (key, app, appIcon,
//     summary, body, image, preview, file, glyph, urgency, timestamp)
//   - our own archive lines (canonical shape below)
// normalizeEntry() folds every shape into the canonical one, keyed by
// "timestamp-originalId" so concurrent writers and re-imports dedupe.
function entryKey(entry) {
  var e = entry || {}
  return String(e.timestamp || 0) + "-" + String(e.originalId || 0)
}

// Canonical entry: { key, app, appIcon, summary, body, image, glyph, urgency,
// timestamp }. Everything the panel draws; nothing it does not. Unknown fields
// (execArgv, expireTimeout, preview, file, id, and any foreign `read` flag)
// are dropped on purpose: a stored execArgv is someone else's command waiting for a click, and the panel never
// runs sender-provided commands.
// Remote or otherwise non-local artwork must never reach the panel's Image
// element: a sender-supplied http(s) URL would make the panel fetch a remote
// resource on render (IP leak / tracking pixel). Only absolute local paths,
// file:// URLs pointing at absolute paths, and bare theme icon names survive;
// everything else normalizes to "" and the panel renders its fallback icon.
function sanitizeImageRef(value) {
  var s = String(value || "")
  if (!s) return ""
  if (s.indexOf("file://") === 0) {
    return s.slice(7).charAt(0) === "/" ? s : ""
  }
  if (s.charAt(0) === "/") return s
  if (s.indexOf("://") !== -1) return ""
  if (s.indexOf("/") !== -1 || s.indexOf("\\") !== -1) return ""
  if (/^[A-Za-z0-9._:+-]+$/.test(s)) return s
  return ""
}

function normalizeEntry(raw) {
  var v = raw || {}
  var timestamp = Number(v.timestamp || 0)
  if (!isFinite(timestamp) || timestamp < 0) timestamp = 0
  // The retired center's archive lines carry a key but no numeric id; the key
  // already is "timestamp-originalId", so adopt it instead of rebuilding a
  // "timestamp-0" that would never match the images stored under the original.
  var rawKey = String(v.key || "")
  var originalId = Number(v.originalId !== undefined ? v.originalId : v.id || 0)
  if ((!isFinite(originalId) || originalId === 0) && rawKey) {
    var tail = Number(rawKey.slice(rawKey.lastIndexOf("-") + 1))
    if (isFinite(tail)) originalId = tail
  }
  if (!isFinite(originalId)) originalId = 0
  var urgency = Number(v.urgency)
  if (!isFinite(urgency)) urgency = 1
  var entry = {
    app: String(v.app || ""),
    appIcon: sanitizeImageRef(v.appIcon),
    summary: String(v.summary || ""),
    body: String(v.body || ""),
    image: sanitizeImageRef(v.image),
    glyph: String(v.glyph || ""),
    urgency: urgency,
    timestamp: timestamp,
    originalId: originalId
  }
  entry.key = rawKey || entryKey(entry)
  // The third-party archive kept a separate preview/file pair for
  // picture-about notifications; when the canonical image is empty but a
  // preview survived, the preview is the picture (sanitized like any other).
  if (!entry.image) entry.image = sanitizeImageRef(v.preview || v.file || "")
  return entry
}

// Parse concatenated one-line JSON files (omarchy popup/history files catted
// together, or our own archive). Torn writes from a crash mid-save are skipped
// line by line so one bad line never takes the archive down with it.
function parseEntryLines(text) {
  var entries = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    try {
      var value = JSON.parse(line)
      if (value && typeof value === "object") entries.push(normalizeEntry(value))
    } catch (e) {
      // Torn line: skip, keep the rest.
    }
  }
  entries.sort(function (a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
  return entries
}

// Merge freshly read entries into the archived ones. Dedupe is by key, so a
// re-read directory, a re-imported third-party archive, and two bar instances
// racing an append all converge instead of duplicating. The optional dismissed
// map (see the tombstone helpers below) excludes already-discarded keys so a
// still-on-disk omarchy file cannot resurrect them.
function mergeEntries(archived, incoming, dismissed) {
  var seen = {}
  var out = []
  function collect(rows) {
    for (var i = 0; i < rows.length; i++) {
      var entry = rows[i]
      if (!entry || seen[entry.key]) continue
      if (dismissed && Object.prototype.hasOwnProperty.call(dismissed, entry.key)) continue
      seen[entry.key] = true
      out.push(entry)
    }
  }
  collect(Array.isArray(incoming) ? incoming : [])
  collect(Array.isArray(archived) ? archived : [])
  out.sort(function (a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
  return out
}

// Dismissed-key tombstones: dismissEntry()/clearAll() remove entries from the
// archive, but omarchy keeps its own 10 history files on disk, so the next
// 3 s poll would re-ingest the same keys. Every discard is therefore recorded
// in dismissed.jsonl (one {"key","at"} JSON object per line) and re-ingested
// keys matching a tombstone are dropped before the merge. The file is
// append-only under concurrency (each discard appends its lines, so two
// per-monitor instances never clobber each other) and bounded by
// trimDismissed(): tombstones expire with the same keepDays as the archive,
// and the count is capped, so the file cannot grow without limit.
function parseDismissedLines(text) {
  var tombstones = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    try {
      var value = JSON.parse(line)
      var key = value && typeof value === "object" ? String(value.key || "") : ""
      if (!key) continue
      var at = value && typeof value === "object" ? Number(value.at) : NaN
      tombstones[key] = (isFinite(at) && at > 0) ? at : 0
    } catch (e) {
      // Torn line: skip, keep the rest.
    }
  }
  return tombstones
}

function serializeDismissed(tombstones) {
  var keys = []
  var src = tombstones || {}
  for (var k in src) {
    if (Object.prototype.hasOwnProperty.call(src, k) && k) keys.push(k)
  }
  keys.sort()
  return keys.map(function (key) {
    return JSON.stringify({ key: key, at: Number(src[key]) || 0 })
  }).join("\n") + "\n"
}

// One JSON line per discarded key for the append-only write path in the
// widget (argv-safe: keys never span lines once stringified).
function dismissedLines(keys, nowMs) {
  var now = Number(nowMs)
  if (!isFinite(now)) now = Date.now()
  var list = Array.isArray(keys) ? keys : [keys]
  var out = []
  for (var i = 0; i < list.length; i++) {
    var key = String(list[i] || "")
    if (key) out.push(JSON.stringify({ key: key, at: now }))
  }
  return out
}

function addDismissed(tombstones, keys, nowMs) {
  var out = {}
  var src = tombstones || {}
  for (var k in src) {
    if (Object.prototype.hasOwnProperty.call(src, k)) out[k] = src[k]
  }
  var now = Number(nowMs)
  if (!isFinite(now)) now = Date.now()
  var list = Array.isArray(keys) ? keys : [keys]
  for (var i = 0; i < list.length; i++) {
    var key = String(list[i] || "")
    if (key) out[key] = now
  }
  return out
}

// Union of two tombstone maps (local state plus a freshly read file): the
// newest discard timestamp wins per key, so converging instances agree.
function mergeDismissed(a, b) {
  var out = {}
  function absorb(src) {
    src = src || {}
    for (var k in src) {
      if (!Object.prototype.hasOwnProperty.call(src, k) || !k) continue
      var at = Number(src[k]) || 0
      if (!(Object.prototype.hasOwnProperty.call(out, k)) || at > out[k]) out[k] = at
    }
  }
  absorb(a)
  absorb(b)
  return out
}

// Timestamp embedded in "timestamp-originalId" keys, for tombstones stored
// without an `at` (or with at 0): lets age-trimming work on those too.
function tombstoneKeyTime(key) {
  var text = String(key || "")
  var dash = text.indexOf("-")
  var ts = Number(dash === -1 ? text : text.slice(0, dash))
  return (isFinite(ts) && ts > 0) ? ts : 0
}

// Bound the tombstone map: entries older than keepDays go first (using `at`,
// falling back to the timestamp embedded in the key), then the oldest beyond
// maxItems. Unknown-age tombstones (time 0) are kept by the age pass and
// evicted oldest-first by the count pass, so the map stays bounded anyway.
function trimDismissed(tombstones, maxItems, keepDays, nowMs) {
  var src = tombstones || {}
  var now = Number(nowMs)
  if (!isFinite(now)) now = Date.now()
  var days = Number(keepDays)
  var cutoff = (isFinite(days) && days > 0) ? now - days * 24 * 60 * 60 * 1000 : -Infinity
  var pairs = []
  for (var k in src) {
    if (!Object.prototype.hasOwnProperty.call(src, k) || !k) continue
    var raw = Number(src[k])
    var at = (isFinite(raw) && raw > 0) ? raw : 0
    var age = at > 0 ? at : tombstoneKeyTime(k)
    if (age > 0 && age < cutoff) continue
    pairs.push({ key: k, at: at })
  }
  pairs.sort(function (a, b) { return a.at - b.at })
  var max = Number(maxItems)
  if (isFinite(max) && max >= 0) pairs = pairs.slice(Math.max(0, pairs.length - Math.floor(max)))
  var out = {}
  for (var i = 0; i < pairs.length; i++) out[pairs[i].key] = pairs[i].at
  return out
}

// Drop archived/incoming entries whose keys were discarded.
function withoutDismissed(entries, dismissed) {
  var rows = Array.isArray(entries) ? entries : []
  if (!dismissed) return rows.slice()
  return rows.filter(function (e) {
    return !e || !Object.prototype.hasOwnProperty.call(dismissed, e.key)
  })
}

// Read/unread state per notification: unlike the old global `seen` timestamp
// (opening the panel cleared the bell), every entry carries its own flag and
// opening the panel marks nothing. The map is { key: { read, at } }, persisted
// append-only in read.jsonl (one {"key","read","at"} JSON object per line)
// with the same contract as the dismissed tombstones: concurrent per-monitor
// instances append their own lines and converge via the file watcher
// (mergeRead: newest `at` wins per key), so no last-writer-wins rewrite can
// ever drop a marking made elsewhere. Absent keys are UNREAD: new arrivals
// need no write to light the bell. trimRead() bounds the map with the same
// keepDays/maxItems contract as the archive, so it cannot grow without limit.
//
// The map never lives inside archive.jsonl entries (normalizeEntry drops a
// foreign `read` field on purpose): the archive is fully rewritten on every
// change, and a read flag stored there would last-writer-wins away concurrent
// markings.
function parseReadLines(text) {
  var state = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    try {
      var value = JSON.parse(line)
      var key = value && typeof value === "object" ? String(value.key || "") : ""
      if (!key) continue
      var raw = value && typeof value === "object" ? value.read : undefined
      var read = !(raw === false || raw === 0 || raw === "false" || raw === "no")
      var at = value && typeof value === "object" ? Number(value.at) : NaN
      if (!Object.prototype.hasOwnProperty.call(state, key) || (isFinite(at) && at > 0 && at > state[key].at)) {
        state[key] = { read: read, at: (isFinite(at) && at > 0) ? at : 0 }
      }
    } catch (e) {
      // Torn line: skip, keep the rest.
    }
  }
  return state
}

function serializeRead(state) {
  var keys = []
  var src = state || {}
  for (var k in src) {
    if (Object.prototype.hasOwnProperty.call(src, k) && k) keys.push(k)
  }
  keys.sort()
  return keys.map(function (key) {
    var cell = src[key] || {}
    return JSON.stringify({ key: key, read: cell.read !== false, at: Number(cell.at) || 0 })
  }).join("\n") + "\n"
}

// One JSON line per (un)marked key for the append-only write path in the
// widget (argv-safe: keys never span lines once stringified).
function readLines(keys, read, nowMs) {
  var now = Number(nowMs)
  if (!isFinite(now)) now = Date.now()
  var flag = !(read === false || read === 0 || read === "false")
  var list = Array.isArray(keys) ? keys : [keys]
  var out = []
  for (var i = 0; i < list.length; i++) {
    var key = String(list[i] || "")
    if (key) out.push(JSON.stringify({ key: key, read: flag, at: now }))
  }
  return out
}

function setRead(state, keys, read, nowMs) {
  var out = {}
  var src = state || {}
  for (var k in src) {
    if (Object.prototype.hasOwnProperty.call(src, k)) out[k] = { read: src[k] && src[k].read !== false, at: Number(src[k] && src[k].at) || 0 }
  }
  var now = Number(nowMs)
  if (!isFinite(now)) now = Date.now()
  var flag = !(read === false || read === 0 || read === "false")
  var list = Array.isArray(keys) ? keys : [keys]
  for (var i = 0; i < list.length; i++) {
    var key = String(list[i] || "")
    if (key) out[key] = { read: flag, at: now }
  }
  return out
}

// Union of two read maps (local state plus a freshly read file): the newest
// marking wins per key, so converging instances agree even when one marked
// read and the other marked unread.
function mergeRead(a, b) {
  var out = {}
  function absorb(src) {
    src = src || {}
    for (var k in src) {
      if (!Object.prototype.hasOwnProperty.call(src, k) || !k) continue
      var cell = src[k] || {}
      var read = cell.read !== false
      var raw = Number(cell.at)
      var at = (isFinite(raw) && raw > 0) ? raw : 0
      if (!Object.prototype.hasOwnProperty.call(out, k) || at > out[k].at) out[k] = { read: read, at: at }
    }
  }
  absorb(a)
  absorb(b)
  return out
}

// Bound the read map: markings older than keepDays go first (using `at`,
// falling back to the timestamp embedded in the key), then the oldest beyond
// maxItems. Same shape as trimDismissed; kept separate so each store's bound
// reads on its own terms.
function trimRead(state, maxItems, keepDays, nowMs) {
  var src = state || {}
  var now = Number(nowMs)
  if (!isFinite(now)) now = Date.now()
  var days = Number(keepDays)
  var cutoff = (isFinite(days) && days > 0) ? now - days * 24 * 60 * 60 * 1000 : -Infinity
  var pairs = []
  for (var k in src) {
    if (!Object.prototype.hasOwnProperty.call(src, k) || !k) continue
    var cell = src[k] || {}
    var raw = Number(cell.at)
    var at = (isFinite(raw) && raw > 0) ? raw : 0
    var age = at > 0 ? at : tombstoneKeyTime(k)
    if (age > 0 && age < cutoff) continue
    pairs.push({ key: k, read: cell.read !== false, at: at })
  }
  pairs.sort(function (a, b) { return a.at - b.at })
  var max = Number(maxItems)
  if (isFinite(max) && max >= 0) pairs = pairs.slice(Math.max(0, pairs.length - Math.floor(max)))
  var out = {}
  for (var i = 0; i < pairs.length; i++) out[pairs[i].key] = { read: pairs[i].read, at: pairs[i].at }
  return out
}

// Absent keys are unread (new arrivals light the bell with no write).
function isRead(state, key) {
  var needle = String(key || "")
  if (!needle || !state) return false
  return Object.prototype.hasOwnProperty.call(state, needle) && state[needle] && state[needle].read !== false
}

// Entries with no marking at all (everything except the migrated/imported
// ones below).
function unreadEntries(entries, state) {
  var rows = Array.isArray(entries) ? entries : []
  return rows.filter(function (e) { return e && !isRead(state, e.key) })
}

// Migration from the old global `seen` timestamp: entries at or below `seen`
// were visible when the panel last opened, so they become read. Anything
// newer stays unread. Returns a map to merge into the read state.
function migrateSeenToRead(entries, seenMs, nowMs) {
  var seen = Number(seenMs || 0)
  if (!isFinite(seen) || seen <= 0) return {}
  var now = Number(nowMs)
  if (!isFinite(now)) now = Date.now()
  var out = {}
  var rows = Array.isArray(entries) ? entries : []
  for (var i = 0; i < rows.length; i++) {
    if (rows[i] && Number(rows[i].timestamp || 0) <= seen) out[rows[i].key] = { read: true, at: now }
  }
  return out
}

// Imported legacy entries (the retired center's archive) always arrive read:
// without this the first run would light the bell over ~950 old rows.
function legacyReadMap(entries, nowMs) {
  var now = Number(nowMs)
  if (!isFinite(now)) now = Date.now()
  var out = {}
  var rows = Array.isArray(entries) ? entries : []
  for (var i = 0; i < rows.length; i++) {
    if (rows[i] && rows[i].key) out[rows[i].key] = { read: true, at: now }
  }
  return out
}

// Bound the archive so a chatty month cannot grow it without limit. Whichever
// of the age cap and the count cap is reached first wins (same contract as the
// retired center's keepDays/maxItems settings).
function trimEntries(entries, maxItems, keepDays, nowMs) {
  var rows = Array.isArray(entries) ? entries.slice() : []
  var now = Number(nowMs)
  if (!isFinite(now)) now = Date.now()
  var days = Number(keepDays)
  if (isFinite(days) && days > 0) {
    var cutoff = now - days * 24 * 60 * 60 * 1000
    rows = rows.filter(function (e) { return Number(e.timestamp || 0) >= cutoff })
  }
  var max = Number(maxItems)
  if (isFinite(max) && max >= 0) rows = rows.slice(0, Math.floor(max))
  return rows
}

// Unread means "no read marking" in the read map (see isRead). A numeric
// second argument keeps the retired contract — entries newer than the
// last-seen timestamp — so the seen-to-read migration stays expressible and
// old callers read honestly during the transition.
function unreadCount(entries, readState) {
  var rows = Array.isArray(entries) ? entries : []
  if (typeof readState === "number" || typeof readState === "string") {
    var seen = Number(readState || 0)
    if (!isFinite(seen)) seen = 0
    var legacy = 0
    for (var i = 0; i < rows.length; i++) {
      if (Number(rows[i].timestamp || 0) > seen) legacy++
    }
    return legacy
  }
  return unreadEntries(rows, readState).length
}

// Plain substring match over sender, subject and message. Deliberately naive:
// the list is capped before this runs, so no index is worth building.
function filterEntries(entries, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return Array.isArray(entries) ? entries.slice() : []
  return (Array.isArray(entries) ? entries : []).filter(function (e) {
    var haystack = (String(e.app || "") + "\n" + String(e.summary || "") + "\n" + String(e.body || "")).toLowerCase()
    return haystack.indexOf(needle) !== -1
  })
}

// Relative age as data, not text: { kind: "now" } for under a minute,
// { kind: "ago", amount, unit } with unit one of minute/minutes/hour/hours/
// day/days/week/weeks, or { kind: "date" } for anything older than 30 days
// (the panel renders a locale short date there). Units stay singular/plural
// keys so the panel can tr() each word; free-form English strings would bypass
// the translation dictionary.
function relativeParts(timestampMs, nowMs) {
  var then = Number(timestampMs || 0)
  var now = Number(nowMs)
  if (!isFinite(now)) now = Date.now()
  var delta = now - then
  if (!isFinite(delta) || delta < 0) delta = 0
  var minute = 60 * 1000
  var hour = 60 * minute
  var day = 24 * hour
  var week = 7 * day
  if (delta < minute) return { kind: "now" }
  if (delta < hour) {
    var minutes = Math.floor(delta / minute)
    return { kind: "ago", amount: minutes, unit: minutes === 1 ? "minute" : "minutes" }
  }
  if (delta < day) {
    var hours = Math.floor(delta / hour)
    return { kind: "ago", amount: hours, unit: hours === 1 ? "hour" : "hours" }
  }
  if (delta < week) {
    var days = Math.floor(delta / day)
    return { kind: "ago", amount: days, unit: days === 1 ? "day" : "days" }
  }
  if (delta < 30 * day) {
    var weeks = Math.floor(delta / week)
    return { kind: "ago", amount: weeks, unit: weeks === 1 ? "week" : "weeks" }
  }
  return { kind: "date" }
}

// The archive on disk: one compact JSON object per line (omarchy's own restore
// cats files together and splits on newlines, so single-line records keep every
// consumer line-addressable).
function serializeArchive(entries) {
  return (Array.isArray(entries) ? entries : []).map(function (e) {
    return JSON.stringify({
      key: e.key, app: e.app, appIcon: e.appIcon, summary: e.summary,
      body: e.body, image: e.image, glyph: e.glyph, urgency: e.urgency,
      timestamp: e.timestamp, originalId: e.originalId
    })
  }).join("\n") + "\n"
}

// Parse the DND preference omarchy persists next to the notification state.
// Read-only fallback for bars whose shell facade cannot hand out the live
// proxy: the file tells the truth about the last-set preference even when the
// toggle itself has to stay disabled.
function parseDndSettings(raw) {
  try {
    var parsed = JSON.parse(String(raw || "").trim() || "{}")
    if (parsed && typeof parsed.dnd === "boolean") return parsed.dnd
  } catch (e) {
  }
  return false
}

// Entries whose image paths still point at omarchy's own images dir die with
// its 10-file trim. Redirect them at our own images dir and report the copies
// the panel must run first: [{ from, to }]. Non-file values (themed icon names,
// dead image:// URLs, already-redirected copies) produce no copy.
function planImageCopies(entries, omarchyImagesDir, ownImagesDir) {
  var rows = Array.isArray(entries) ? entries : []
  var fromPrefix = String(omarchyImagesDir || "")
  var copies = []
  var rewritten = rows.map(function (e) {
    var out = {}
    for (var key in e) out[key] = e[key];
    ["appIcon", "image"].forEach(function (role) {
      var value = String(out[role] || "")
      var path = value.indexOf("file://") === 0 ? value.slice(7) : value
      if (path.charAt(0) !== "/" || fromPrefix === "" || path.indexOf(fromPrefix) !== 0) return
      var copy = String(ownImagesDir || "") + String(e.key || "unknown") + "-" + role
      if (path === copy) return
      copies.push({ from: path, to: copy })
      out[role] = "file://" + copy
    })
    return out
  })
  return { entries: rewritten, copies: copies }
}

// Small JSON blob for the state/test IpcHandler: totals plus the newest subject
// line so a post-install check can eyeball one call. The second argument is
// the read map (a legacy numeric `seen` still reads honestly).
function stateSummary(entries, readState) {
  var rows = Array.isArray(entries) ? entries : []
  return {
    total: rows.length,
    unread: unreadCount(rows, readState),
    newest: rows.length > 0 ? String(rows[0].summary || "") : ""
  }
}

// Deterministic synthetic entries for the `seed` IPC test verb: verifiable
// without touching the user's real archive (seeded entries carry app
// "orbital-seed" and decreasing timestamps so ordering is assertable).
function makeSeedEntries(count, nowMs) {
  var n = Math.max(0, Math.min(5000, Math.floor(Number(count) || 0)))
  var now = Number(nowMs)
  if (!isFinite(now)) now = Date.now()
  var out = []
  for (var i = 0; i < n; i++) {
    var entry = normalizeEntry({
      app: "orbital-seed",
      appIcon: "",
      summary: "Seed notification " + (i + 1),
      body: "Synthetic entry for post-install verification.",
      image: "",
      glyph: "",
      urgency: 1,
      timestamp: now - i * 1000,
      originalId: 900000 + i
    })
    out.push(entry)
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    entryKey: entryKey,
    sanitizeImageRef: sanitizeImageRef,
    normalizeEntry: normalizeEntry,
    parseEntryLines: parseEntryLines,
    mergeEntries: mergeEntries,
    parseDismissedLines: parseDismissedLines,
    serializeDismissed: serializeDismissed,
    dismissedLines: dismissedLines,
    addDismissed: addDismissed,
    mergeDismissed: mergeDismissed,
    trimDismissed: trimDismissed,
    withoutDismissed: withoutDismissed,
    trimEntries: trimEntries,
    parseReadLines: parseReadLines,
    serializeRead: serializeRead,
    readLines: readLines,
    setRead: setRead,
    mergeRead: mergeRead,
    trimRead: trimRead,
    isRead: isRead,
    unreadEntries: unreadEntries,
    migrateSeenToRead: migrateSeenToRead,
    legacyReadMap: legacyReadMap,
    unreadCount: unreadCount,
    filterEntries: filterEntries,
    relativeParts: relativeParts,
    serializeArchive: serializeArchive,
    parseDndSettings: parseDndSettings,
    planImageCopies: planImageCopies,
    stateSummary: stateSummary,
    makeSeedEntries: makeSeedEntries
  }
}
