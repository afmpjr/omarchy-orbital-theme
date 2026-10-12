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
// (execArgv, expireTimeout, preview, file, id) are dropped on purpose: a stored
// execArgv is someone else's command waiting for a click, and the panel never
// runs sender-provided commands.
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
    appIcon: String(v.appIcon || ""),
    summary: String(v.summary || ""),
    body: String(v.body || ""),
    image: String(v.image || ""),
    glyph: String(v.glyph || ""),
    urgency: urgency,
    timestamp: timestamp,
    originalId: originalId
  }
  entry.key = rawKey || entryKey(entry)
  // The third-party archive kept a separate preview/file pair for
  // picture-about notifications; when the canonical image is empty but a
  // preview survived, the preview is the picture.
  if (!entry.image) entry.image = String(v.preview || v.file || "")
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
// racing an append all converge instead of duplicating.
function mergeEntries(archived, incoming) {
  var seen = {}
  var out = []
  function collect(rows) {
    for (var i = 0; i < rows.length; i++) {
      var entry = rows[i]
      if (!entry || seen[entry.key]) continue
      seen[entry.key] = true
      out.push(entry)
    }
  }
  collect(Array.isArray(incoming) ? incoming : [])
  collect(Array.isArray(archived) ? archived : [])
  out.sort(function (a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
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

// Entries newer than the last-seen timestamp are unread. Opening the panel
// writes seen = now, which is what clears the bell.
function unreadCount(entries, seenMs) {
  var seen = Number(seenMs || 0)
  if (!isFinite(seen)) seen = 0
  var count = 0
  var rows = Array.isArray(entries) ? entries : []
  for (var i = 0; i < rows.length; i++) {
    if (Number(rows[i].timestamp || 0) > seen) count++
  }
  return count
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
// line so a post-install check can eyeball one call.
function stateSummary(entries, seenMs) {
  var rows = Array.isArray(entries) ? entries : []
  return {
    total: rows.length,
    unread: unreadCount(rows, seenMs),
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
    normalizeEntry: normalizeEntry,
    parseEntryLines: parseEntryLines,
    mergeEntries: mergeEntries,
    trimEntries: trimEntries,
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
