// DoctorModel.js — Pure data model and parsing logic for omarchy-doctor.
// Kept Qt-free so it can be thoroughly unit tested under Node.js.
// Complies with the Orbital theme design tokens and failure resilience rules.

var _i18n = null;
if (typeof require !== "undefined") {
  try {
    _i18n = require("./I18n.js");
  } catch (e) {}
}

function setI18n(instance) {
  _i18n = instance;
}

function getI18n() {
  return _i18n;
}

function tr(key, params, locale) {
  if (_i18n && typeof _i18n.t === "function") {
    return _i18n.t(key, params, locale);
  }
  if (params !== undefined && params !== null) {
    var args = Array.isArray(params) ? params : [params];
    var idx = 0;
    return String(key).replace(/%[sd]/g, function() {
      return idx < args.length ? String(args[idx++]) : "";
    });
  }
  return key;
}

/**
 * Parses raw JSON text safely with exception containment.
 * Never throws or crashes the host QML engine on truncated or missing files.
 * @param {string} rawText - Raw content of state.json
 * @returns {{ valid: boolean, state: object|null, error?: string }}
 */
function parseState(rawText) {
  if (rawText === null || rawText === undefined) {
    return { valid: false, state: null, error: "Null or undefined input" };
  }
  var text = String(rawText).trim();
  if (text.length === 0) {
    return { valid: false, state: null, error: "Empty input" };
  }
  try {
    var parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return { valid: false, state: null, error: "State must be an object" };
    }
    // Guarantee minimal safe properties
    if (!parsed.metrics || typeof parsed.metrics !== "object") {
      parsed.metrics = {};
    }
    if (!Array.isArray(parsed.failed_units)) {
      parsed.failed_units = [];
    }
    if (!Array.isArray(parsed.findings)) {
      parsed.findings = [];
    }
    if (parsed.failed_units.length === 0 && parsed.findings.length > 0) {
      for (var fi = 0; fi < parsed.findings.length; fi++) {
        var fObj = parsed.findings[fi];
        if (fObj && (fObj.id === "failed_services" || fObj.id === "failed_units") && typeof fObj.title === "string") {
          var colonIdx = fObj.title.indexOf(":");
          if (colonIdx !== -1) {
            var rawUnits = fObj.title.slice(colonIdx + 1).split(",");
            for (var ui = 0; ui < rawUnits.length; ui++) {
              var cleaned = rawUnits[ui].replace(/\s*\([^)]*\)\s*/g, "").trim();
              if (cleaned.length > 0) {
                parsed.failed_units.push({ name: cleaned });
              }
            }
          }
        }
      }
    }
    if (!Array.isArray(parsed.recent_actions)) {
      parsed.recent_actions = [];
    }
    return { valid: true, state: parsed };
  } catch (err) {
    return { valid: false, state: null, error: err.message };
  }
}

/**
 * Resolves the overarching health status of the system.
 * Possible returns: "ok" | "warning" | "critical" | "stale" | "stopped"
 *
 * @param {object|null} doctorState - The parsed state object
 * @param {boolean} isStateValid - Whether the file parsed cleanly
 * @param {number} [lastModifiedEpochMs] - Optional mtime fallback
 * @param {number} [nowEpochMs] - Current timestamp for deterministic testing
 * @returns {string} Macro status
 */
function resolveStatus(doctorState, isStateValid, lastModifiedEpochMs, nowEpochMs) {
  if (!isStateValid || !doctorState) {
    return "stopped";
  }

  // Service daemon active state
  if (doctorState.service && doctorState.service.active === false) {
    return "stopped";
  }

  // Stale detection: more than 60 seconds (2 cycles) without an update
  var now = (nowEpochMs !== undefined && nowEpochMs !== null) ? Number(nowEpochMs) : Date.now();
  var updatedEpoch = 0;
  if (doctorState.updated_at) {
    var parsed = Date.parse(doctorState.updated_at);
    if (!isNaN(parsed) && parsed > 0) {
      updatedEpoch = parsed;
    }
  }
  if (updatedEpoch === 0 && lastModifiedEpochMs) {
    updatedEpoch = Number(lastModifiedEpochMs);
  }

  if (updatedEpoch === 0 || (now - updatedEpoch) > 60000) {
    return "stale";
  }

  // Hardware SMART failure check
  if (doctorState.smart && Array.isArray(doctorState.smart.devices)) {
    for (var d = 0; d < doctorState.smart.devices.length; d++) {
      var dev = doctorState.smart.devices[d];
      if (dev && (dev.failing === true || String(dev.health).toUpperCase() === "FAILING")) {
        return "critical";
      }
    }
  }

  // Systemd failed units check
  // A "warning" verdict from the daemon must not be escalated to "critical"
  // when every finding is merely warning/info. However, when findings are
  // absent (e.g. tests populating failed_units directly) or an explicit
  // critical finding exists, failed units remain critical.
  if (Array.isArray(doctorState.failed_units) && doctorState.failed_units.length > 0) {
    var hasCriticalFinding = false;
    var hasFindings = Array.isArray(doctorState.findings) && doctorState.findings.length > 0;
    if (hasFindings) {
      for (var cf = 0; cf < doctorState.findings.length; cf++) {
        var cfFinding = doctorState.findings[cf];
        if (cfFinding && cfFinding.severity === "critical") {
          hasCriticalFinding = true;
          break;
        }
      }
    }
    if (doctorState.status !== "warning" || hasCriticalFinding || !hasFindings) {
      return "critical";
    }
  }

  // Explicit critical verdict
  if (doctorState.status === "critical") {
    return "critical";
  }

  // Resource thresholds: Disk partitions
  var disk = doctorState.metrics && doctorState.metrics.disk;
  if (disk) {
    if (typeof disk.percent_used === "number" && disk.percent_used >= 90.0) {
      return "critical";
    }
    if (Array.isArray(disk.partitions)) {
      for (var p = 0; p < disk.partitions.length; p++) {
        var part = disk.partitions[p];
        if (part && typeof part.percent_used === "number" && part.percent_used >= 90.0) {
          return "critical";
        }
      }
    }
  }

  // Resource thresholds: Kernel PSI (Pressure Stall Information) >= 25% is Critical
  var psi = doctorState.metrics && doctorState.metrics.psi;
  if (psi) {
    var psiCpu = psi.cpu && ((psi.cpu.some && psi.cpu.some.avg10) || psi.cpu.some_avg10);
    var psiMem = psi.memory && ((psi.memory.some && psi.memory.some.avg10) || psi.memory.some_avg10);
    var psiIo = psi.io && ((psi.io.some && psi.io.some.avg10) || psi.io.some_avg10);
    if ((typeof psiCpu === "number" && psiCpu >= 25.0) ||
        (typeof psiMem === "number" && psiMem >= 25.0) ||
        (typeof psiIo === "number" && psiIo >= 25.0)) {
      return "critical";
    }
  }

  // Explicit warning verdict
  if (doctorState.status === "warning") {
    return "warning";
  }

  // Warning thresholds: Disk 80% to 89%
  if (disk) {
    if (typeof disk.percent_used === "number" && disk.percent_used >= 80.0) {
      return "warning";
    }
    if (Array.isArray(disk.partitions)) {
      for (var p2 = 0; p2 < disk.partitions.length; p2++) {
        var part2 = disk.partitions[p2];
        if (part2 && typeof part2.percent_used === "number" && part2.percent_used >= 80.0) {
          return "warning";
        }
      }
    }
  }

  // Warning thresholds: PSI >= 15% is Warning
  if (psi) {
    var pCpu = psi.cpu && ((psi.cpu.some && psi.cpu.some.avg10) || psi.cpu.some_avg10);
    var pMem = psi.memory && ((psi.memory.some && psi.memory.some.avg10) || psi.memory.some_avg10);
    var pIo = psi.io && ((psi.io.some && psi.io.some.avg10) || psi.io.some_avg10);
    if ((typeof pCpu === "number" && pCpu >= 15.0) ||
        (typeof pMem === "number" && pMem >= 15.0) ||
        (typeof pIo === "number" && pIo >= 15.0)) {
      return "warning";
    }
  }

  // Findings severity check
  if (Array.isArray(doctorState.findings)) {
    for (var f = 0; f < doctorState.findings.length; f++) {
      var finding = doctorState.findings[f];
      if (finding && finding.severity === "critical") return "critical";
      if (finding && finding.severity === "warning") return "warning";
    }
  }

  if (doctorState.status === "ok") {
    return "ok";
  }

  return "ok";
}

/**
 * Formats a byte quantity into a human-readable string.
 * @param {number|null|undefined} bytes - Number of bytes
 * @returns {string} Formatted string (e.g. "1.8 GiB", "142.0 GB", "0 B")
 */
function formatBytes(bytes) {
  if (bytes === null || bytes === undefined || isNaN(bytes)) {
    return "N/D";
  }
  var n = Number(bytes);
  if (n <= 0) return "0 B";
  var k = 1024;
  var units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
  var i = Math.floor(Math.log(n) / Math.log(k));
  if (i >= units.length) i = units.length - 1;
  var formatted = (n / Math.pow(k, i)).toFixed(1);
  // Strip trailing .0 if integer
  if (formatted.slice(-2) === ".0") {
    formatted = formatted.slice(0, -2);
  }
  return formatted + " " + units[i];
}

/**
 * Formats a percentage value.
 * @param {number|null|undefined} value - Numeric percentage
 * @returns {string} Formatted percentage or "N/D"
 */
function formatPercent(value) {
  if (value === null || value === undefined || isNaN(value)) {
    return "N/D";
  }
  var v = Number(value);
  var rounded = Math.round(v * 10) / 10;
  return rounded + "%";
}

/**
 * Returns a human-friendly relative time string localized to the current locale.
 * Default canonical language: English ("now", "14s ago", "2m ago", "1h ago", "2d ago").
 * Localized Portuguese when in pt ("agora", "há 14s", "há 2m", "há 1h", "há 2d").
 * @param {string|number} isoOrTimestamp - ISO 8601 string or epoch milliseconds
 * @param {number} [nowEpochMs] - Current timestamp
 * @param {string} [locale] - Optional locale override ("en" or "pt")
 * @returns {string} Relative time string
 */
function relativeTime(isoOrTimestamp, nowEpochMs, locale) {
  if (!isoOrTimestamp) return "N/D";
  var epoch = typeof isoOrTimestamp === "number" ? isoOrTimestamp : Date.parse(isoOrTimestamp);
  if (isNaN(epoch) || epoch <= 0) return "N/D";

  var now = (nowEpochMs !== undefined && nowEpochMs !== null) ? Number(nowEpochMs) : Date.now();
  var deltaSec = Math.max(0, Math.floor((now - epoch) / 1000));

  if (deltaSec < 5) return tr("now", null, locale);
  if (deltaSec < 60) return tr("%ss ago", [deltaSec], locale);
  var deltaMin = Math.floor(deltaSec / 60);
  if (deltaMin < 60) return tr("%sm ago", [deltaMin], locale);
  var deltaHours = Math.floor(deltaMin / 60);
  if (deltaHours < 24) return tr("%sh ago", [deltaHours], locale);
  var deltaDays = Math.floor(deltaHours / 24);
  return tr("%sd ago", [deltaDays], locale);
}

/**
 * Generates descriptive tooltip text for the bar button hover state.
 * @param {object|null} doctorState - State object
 * @param {string} status - Resolved status
 * @param {string} [locale] - Optional locale override
 * @returns {string} Tooltip string
 */
function compactSummary(text) {
  if (!text) return "";
  var s = String(text).replace(/^Why it is slow:\s*/i, "").trim();
  var dotIdx = s.indexOf(". Failed units:");
  if (dotIdx !== -1) {
    s = s.slice(0, dotIdx);
  }
  if (s.length > 64) {
    return s.slice(0, 61) + "...";
  }
  return s;
}

function tooltipFor(doctorState, status, locale) {
  if (status === "stopped") {
    return tr("omarchy-doctor: Inactive Monitor", null, locale);
  }
  if (status === "stale") {
    return tr("omarchy-doctor: Data Stale", null, locale);
  }
  if (status === "critical") {
    var critDetail = "";
    if (doctorState) {
      if (Array.isArray(doctorState.failed_units) && doctorState.failed_units.length > 0) {
        critDetail = tr("%d failed unit(s)", [doctorState.failed_units.length], locale);
      } else if (doctorState.metrics && doctorState.metrics.disk && doctorState.metrics.disk.percent_used >= 90) {
        critDetail = tr("Disk at %s", [Math.round(doctorState.metrics.disk.percent_used) + "%"], locale);
      } else if (doctorState.summary) {
        critDetail = compactSummary(doctorState.summary);
      }
    }
    return tr("omarchy-doctor: CRITICAL (%s)", [critDetail || tr("Critical condition", null, locale)], locale);
  }
  if (status === "warning") {
    var warnDetail = "";
    if (doctorState) {
      if (doctorState.metrics && doctorState.metrics.disk && doctorState.metrics.disk.percent_used >= 80) {
        warnDetail = tr("Disk at %s", [Math.round(doctorState.metrics.disk.percent_used) + "%"], locale);
      } else if (doctorState.summary) {
        warnDetail = compactSummary(doctorState.summary);
      }
    }
    return tr("omarchy-doctor: Attention (%s)", [warnDetail || tr("Attention needed", null, locale)], locale);
  }
  return tr("omarchy-doctor: Healthy System", null, locale);
}

/**
 * Resolves color for status dot according to Orbital tokens.
 * @param {string} status - Macro status
 * @param {object} [tokens] - Theme tokens
 * @returns {string} Color hex or rgba
 */
function colorForStatus(status, tokens) {
  var t = tokens || {};
  if (status === "critical") {
    return t.dangerBase || t.red || "#E86A6A";
  }
  if (status === "warning") {
    return t.yellow || "#D9B66A";
  }
  if (status === "stale" || status === "stopped") {
    return t.muted || "#60758C";
  }
  return t.green || "#7BC29A";
}

/**
 * Returns color gradient for PSI pressure gauge cards.
 * @param {number|null|undefined} valuePercent - PSI avg10 value
 * @param {object} [tokens] - Theme tokens
 * @returns {string} Color hex
 */
function psiColor(valuePercent, tokens) {
  var t = tokens || {};
  if (valuePercent === null || valuePercent === undefined || isNaN(valuePercent)) {
    return t.dark_fg || "#91A4BB";
  }
  var v = Number(valuePercent);
  if (v >= 25.0) {
    return t.dangerBase || t.red || "#E86A6A";
  }
  if (v >= 15.0) {
    return t.yellow || "#D9B66A";
  }
  return t.dark_fg || "#91A4BB";
}

/**
 * Returns color for disk space progress bars.
 * @param {number|null|undefined} percent - Percent used
 * @param {object} [tokens] - Theme tokens
 * @returns {string} Color hex
 */
function diskColor(percent, tokens) {
  var t = tokens || {};
  if (percent === null || percent === undefined || isNaN(percent)) {
    return t.accent || "#39A9FF";
  }
  var p = Number(percent);
  if (p >= 90.0) {
    return t.dangerBase || t.red || "#E86A6A";
  }
  if (p >= 80.0) {
    return t.yellow || "#D9B66A";
  }
  return t.accent || "#39A9FF";
}

/**
 * Generates summary description for systemd units.
 * @param {Array|null} failedUnits - List of failed units
 * @param {string} [locale] - Optional locale override
 * @returns {{ ok: boolean, text: string, count: number }}
 */
function systemdStatusSummary(failedUnits, locale) {
  var list = Array.isArray(failedUnits) ? failedUnits : [];
  if (list.length === 0) {
    return {
      ok: true,
      text: tr("Systemd: 0 failed units (all operational)", null, locale),
      count: 0
    };
  }
  var unknownName = tr("unknown unit", null, locale);
  var names = list.map(function(u) {
    return (u && (u.name || u.unit)) ? (u.name || u.unit) : unknownName;
  }).join(", ");
  return {
    ok: false,
    text: tr("%d failed unit(s): %s", [list.length, names], locale),
    count: list.length
  };
}

/**
 * Generates summary description for SMART storage health.
 * @param {object|null} smart - SMART metadata
 * @param {string} [locale] - Optional locale override
 * @returns {{ available: boolean, ok: boolean, text: string }}
 */
function smartStatusSummary(smart, locale) {
  if (!smart || smart.available !== true) {
    return {
      available: false,
      ok: true,
      text: tr("SMART: Requires root (permission pending)", null, locale)
    };
  }
  var devices = Array.isArray(smart.devices) ? smart.devices : [];
  if (devices.length === 0) {
    return {
      available: true,
      ok: true,
      text: tr("SMART: No devices detected", null, locale)
    };
  }
  var failingDevices = [];
  var parts = [];
  var defaultDiskName = tr("disk", null, locale);
  for (var i = 0; i < devices.length; i++) {
    var dev = devices[i];
    if (!dev) continue;
    var name = dev.device || (dev.path ? dev.path.replace("/dev/", "") : defaultDiskName);
    var health = dev.health || (dev.failing ? "FAILING" : "OK");
    var temp = (dev.temperature || dev.temperature_celsius) ? (dev.temperature || dev.temperature_celsius) + "°C" : "";
    if (dev.failing === true || String(health).toUpperCase() === "FAILING") {
      failingDevices.push(name);
    }
    parts.push("/dev/" + name + " (" + health + (temp ? ", " + temp : "") + ")");
  }
  if (failingDevices.length > 0) {
    return {
      available: true,
      ok: false,
      text: tr("WARNING: Imminent physical failure on %s!", [failingDevices.join(", ")], locale)
    };
  }
  return {
    available: true,
    ok: true,
    text: tr("Physical Disks: %s", [parts.join(" • ")], locale)
  };
}

/**
 * Maps an automatic action type to an appropriate symbolic SVG icon.
 * @param {string} actionType - The type of action performed
 * @returns {string} Freedesktop symbolic icon name
 */
function recentActionIcon(actionType) {
  var t = String(actionType || "").toLowerCase();
  if (t === "pacman_cache" || t === "packages") {
    return "application-x-executable-symbolic";
  }
  if (t === "docker_cache" || t === "docker_volumes" || t === "docker_images") {
    return "emblem-system-symbolic";
  }
  if (t === "systemd_journal" || t === "journal" || t === "old_logs") {
    return "preferences-desktop-appearance-symbolic";
  }
  return "emblem-system-symbolic";
}

/**
 * Resolves metadata for the header status pill tag.
 * @param {string} status - Macro status
 * @param {string} [locale] - Optional locale override
 * @returns {{ text: string, status: string }}
 */
function badgeInfo(status, locale) {
  if (status === "ok") {
    return { text: tr("SYSTEM HEALTHY", null, locale), status: "ok" };
  }
  if (status === "warning") {
    return { text: tr("ATTENTION NEEDED", null, locale), status: "warning" };
  }
  if (status === "critical") {
    return { text: tr("CRITICAL CONDITION", null, locale), status: "critical" };
  }
  if (status === "stale") {
    return { text: tr("DATA STALE", null, locale), status: "stale" };
  }
  return { text: tr("MONITOR DISCONNECTED", null, locale), status: "stopped" };
}

// Node.js module export compatibility (for testing without Qt)
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    parseState: parseState,
    resolveStatus: resolveStatus,
    formatBytes: formatBytes,
    formatPercent: formatPercent,
    relativeTime: relativeTime,
    tooltipFor: tooltipFor,
    colorForStatus: colorForStatus,
    psiColor: psiColor,
    diskColor: diskColor,
    systemdStatusSummary: systemdStatusSummary,
    smartStatusSummary: smartStatusSummary,
    recentActionIcon: recentActionIcon,
    badgeInfo: badgeInfo,
    setI18n: setI18n,
    getI18n: getI18n
  };
}
