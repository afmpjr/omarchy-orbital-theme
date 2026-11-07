// test/doctor-model-test.js
// Unit tests for DoctorModel.js and I18n.js using Node.js assert.
// Validates all scenarios and edge cases from Patricia's QA Matrix (ST-44 / ST-45)
// and canonical internationalization (English default + PT-BR via locale).

var assert = require("assert");
var fs = require("fs");
var path = require("path");
var Model = require(path.join(__dirname, "..", "plugins", "orbital.doctor", "DoctorModel.js"));
var I18n = require(path.join(__dirname, "..", "plugins", "orbital.doctor", "I18n.js"));

var passed = 0;
function check(name, fn) {
  fn();
  passed++;
  console.log("ok - " + name);
}

// Helper to load fixture JSON
function loadFixture(filename) {
  var fullPath = path.join(__dirname, "fixtures", "doctor", filename);
  return fs.readFileSync(fullPath, "utf8");
}

console.log("Starting omarchy-doctor Model Unit Tests...");

var activeLocale = I18n.detectLocale();
var isPt = activeLocale === "pt";

// 0. I18n Module Core Resolution & Fallback Behavior
check("I18n module detects locale and strictly defaults to English on null, C, en_US", function() {
  // Test fallback on various locale parameters
  assert.strictEqual(I18n.t("SYSTEM HEALTHY", null, "en"), "SYSTEM HEALTHY");
  assert.strictEqual(I18n.t("SYSTEM HEALTHY", null, "C"), "SYSTEM HEALTHY");
  assert.strictEqual(I18n.t("SYSTEM HEALTHY", null, "en_US"), "SYSTEM HEALTHY");
  assert.strictEqual(I18n.t("SYSTEM HEALTHY", null, "en_GB"), "SYSTEM HEALTHY");
  assert.strictEqual(I18n.t("SYSTEM HEALTHY", null, "fr_FR"), "SYSTEM HEALTHY");
  assert.strictEqual(I18n.t("SYSTEM HEALTHY", null, "pt"), "SISTEMA SAUDÁVEL");
  assert.strictEqual(I18n.t("SYSTEM HEALTHY", null, "pt_BR"), "SISTEMA SAUDÁVEL");

  // Parameter formatting
  assert.strictEqual(I18n.t("%d failed unit(s): %s", [1, "test.service"], "en"), "1 failed unit(s): test.service");
  assert.strictEqual(I18n.t("%d failed unit(s): %s", [1, "test.service"], "pt"), "1 unit(s) em falha: test.service");

  // Relative clock keys
  assert.strictEqual(I18n.t("now", null, "en"), "now");
  assert.strictEqual(I18n.t("now", null, "pt"), "agora");
  assert.strictEqual(I18n.t("%ss ago", [15], "en"), "15s ago");
  assert.strictEqual(I18n.t("%ss ago", [15], "pt"), "há 15s");
});

// 1. Nominal Healthy Scenario (fixture-ok.json)
check("nominal healthy fixture parses cleanly and resolves to 'ok'", function() {
  var raw = loadFixture("fixture-ok.json");
  var parsed = Model.parseState(raw);
  assert.strictEqual(parsed.valid, true, "State should be valid");
  assert.ok(parsed.state !== null, "State object must not be null");

  // Synchronous time check within 10s of updated_at (2026-10-27T20:50:00Z)
  var testNow = Date.parse("2026-10-27T20:50:14.000Z");
  var status = Model.resolveStatus(parsed.state, true, 0, testNow);
  assert.strictEqual(status, "ok", "Healthy state should resolve to 'ok'");

  // Verify active locale
  var tooltip = Model.tooltipFor(parsed.state, status);
  assert.strictEqual(tooltip, isPt ? "omarchy-doctor: Sistema Saudável" : "omarchy-doctor: Healthy System");

  // Verify explicit locale overrides
  assert.strictEqual(Model.tooltipFor(parsed.state, status, "en"), "omarchy-doctor: Healthy System");
  assert.strictEqual(Model.tooltipFor(parsed.state, status, "pt"), "omarchy-doctor: Sistema Saudável");
  assert.strictEqual(Model.tooltipFor(parsed.state, status, "C"), "omarchy-doctor: Healthy System");
  assert.strictEqual(Model.tooltipFor(parsed.state, status, "en_US"), "omarchy-doctor: Healthy System");

  var color = Model.colorForStatus(status, { green: "#7BC29A" });
  assert.strictEqual(color, "#7BC29A");

  var badge = Model.badgeInfo(status);
  assert.strictEqual(badge.text, isPt ? "SISTEMA SAUDÁVEL" : "SYSTEM HEALTHY");
  assert.strictEqual(Model.badgeInfo(status, "en").text, "SYSTEM HEALTHY");
  assert.strictEqual(Model.badgeInfo(status, "pt").text, "SISTEMA SAUDÁVEL");
  assert.strictEqual(Model.badgeInfo(status, "C").text, "SYSTEM HEALTHY");
  assert.strictEqual(Model.badgeInfo(status, "en_US").text, "SYSTEM HEALTHY");

  var sysSummary = Model.systemdStatusSummary(parsed.state.failed_units);
  assert.strictEqual(sysSummary.ok, true);
  assert.strictEqual(sysSummary.count, 0);
  assert.strictEqual(sysSummary.text, isPt ? "Systemd: 0 units em falha (todas operando)" : "Systemd: 0 failed units (all operational)");
  assert.strictEqual(Model.systemdStatusSummary(parsed.state.failed_units, "en").text, "Systemd: 0 failed units (all operational)");
  assert.strictEqual(Model.systemdStatusSummary(parsed.state.failed_units, "pt").text, "Systemd: 0 units em falha (todas operando)");

  var smartSummary = Model.smartStatusSummary(parsed.state.smart);
  assert.strictEqual(smartSummary.available, false);
  assert.strictEqual(smartSummary.text, isPt ? "SMART: Requer root (autorização pendente)" : "SMART: Requires root (permission pending)");
  assert.strictEqual(Model.smartStatusSummary(parsed.state.smart, "en").text, "SMART: Requires root (permission pending)");
  assert.strictEqual(Model.smartStatusSummary(parsed.state.smart, "pt").text, "SMART: Requer root (autorização pendente)");
});

// 2. Warning Scenario — High Disk Usage 84% (fixture-warn-disk.json)
check("warning disk usage 84% resolves to 'warning'", function() {
  var raw = loadFixture("fixture-warn-disk.json");
  var parsed = Model.parseState(raw);
  assert.strictEqual(parsed.valid, true);

  var testNow = Date.parse("2026-10-27T20:50:10.000Z");
  var status = Model.resolveStatus(parsed.state, true, 0, testNow);
  assert.strictEqual(status, "warning", "84% disk should trigger warning");

  var tooltip = Model.tooltipFor(parsed.state, status);
  assert.strictEqual(tooltip, isPt ? "omarchy-doctor: Atenção (Disco em 84%)" : "omarchy-doctor: Attention (Disk at 84%)");
  assert.strictEqual(Model.tooltipFor(parsed.state, status, "en"), "omarchy-doctor: Attention (Disk at 84%)");
  assert.strictEqual(Model.tooltipFor(parsed.state, status, "pt"), "omarchy-doctor: Atenção (Disco em 84%)");

  var color = Model.colorForStatus(status, { yellow: "#D9B66A" });
  assert.strictEqual(color, "#D9B66A");

  var dColor = Model.diskColor(parsed.state.metrics.disk.percent_used, { yellow: "#D9B66A", accent: "#39A9FF" });
  assert.strictEqual(dColor, "#D9B66A", "Disk color should be warning yellow");

  var badge = Model.badgeInfo(status);
  assert.strictEqual(badge.text, isPt ? "ATENÇÃO NECESSÁRIA" : "ATTENTION NEEDED");
  assert.strictEqual(Model.badgeInfo(status, "en").text, "ATTENTION NEEDED");
  assert.strictEqual(Model.badgeInfo(status, "pt").text, "ATENÇÃO NECESSÁRIA");
});

// 3. Critical Scenario — Disk 93% and Failed Systemd Unit (fixture-crit-dual.json)
check("critical dual threshold (disk 93% + failed unit) resolves to 'critical'", function() {
  var raw = loadFixture("fixture-crit-dual.json");
  var parsed = Model.parseState(raw);
  assert.strictEqual(parsed.valid, true);

  var testNow = Date.parse("2026-10-27T20:50:10.000Z");
  var status = Model.resolveStatus(parsed.state, true, 0, testNow);
  assert.strictEqual(status, "critical", "Should resolve to critical");

  var tooltip = Model.tooltipFor(parsed.state, status);
  assert.strictEqual(tooltip, isPt ? "omarchy-doctor: CRÍTICO (1 unit(s) em falha)" : "omarchy-doctor: CRITICAL (1 failed unit(s))");
  assert.strictEqual(Model.tooltipFor(parsed.state, status, "en"), "omarchy-doctor: CRITICAL (1 failed unit(s))");
  assert.strictEqual(Model.tooltipFor(parsed.state, status, "pt"), "omarchy-doctor: CRÍTICO (1 unit(s) em falha)");

  var color = Model.colorForStatus(status, { dangerBase: "#E86A6A" });
  assert.strictEqual(color, "#E86A6A");

  var dColor = Model.diskColor(parsed.state.metrics.disk.percent_used, { dangerBase: "#E86A6A" });
  assert.strictEqual(dColor, "#E86A6A", "93% disk color should be critical danger");

  var sysSummary = Model.systemdStatusSummary(parsed.state.failed_units);
  assert.strictEqual(sysSummary.ok, false);
  assert.strictEqual(sysSummary.count, 1);
  assert.ok(sysSummary.text.indexOf("backup-sync.service") !== -1);
  assert.strictEqual(sysSummary.text, isPt ? "1 unit(s) em falha: backup-sync.service" : "1 failed unit(s): backup-sync.service");
  assert.strictEqual(Model.systemdStatusSummary(parsed.state.failed_units, "en").text, "1 failed unit(s): backup-sync.service");
  assert.strictEqual(Model.systemdStatusSummary(parsed.state.failed_units, "pt").text, "1 unit(s) em falha: backup-sync.service");

  var badge = Model.badgeInfo(status);
  assert.strictEqual(badge.text, isPt ? "CONDIÇÃO CRÍTICA" : "CRITICAL CONDITION");
  assert.strictEqual(Model.badgeInfo(status, "en").text, "CRITICAL CONDITION");
  assert.strictEqual(Model.badgeInfo(status, "pt").text, "CONDIÇÃO CRÍTICA");
});

// 4. Stale Data Detection (>60s elapsed without state updates)
check("detects stale state when timestamp exceeds 60s freshness window", function() {
  var raw = loadFixture("fixture-stale.json");
  var parsed = Model.parseState(raw);
  assert.strictEqual(parsed.valid, true);

  // Fixture has updated_at = 2026-10-27T20:30:00Z. Check at 20:50:00Z (20 min later)
  var testNow = Date.parse("2026-10-27T20:50:00.000Z");
  var status = Model.resolveStatus(parsed.state, true, 0, testNow);
  assert.strictEqual(status, "stale", "Elapsed time > 60s must yield 'stale'");

  var tooltip = Model.tooltipFor(parsed.state, status);
  assert.strictEqual(tooltip, isPt ? "omarchy-doctor: Dados Desatualizados" : "omarchy-doctor: Data Stale");
  assert.strictEqual(Model.tooltipFor(parsed.state, status, "en"), "omarchy-doctor: Data Stale");
  assert.strictEqual(Model.tooltipFor(parsed.state, status, "pt"), "omarchy-doctor: Dados Desatualizados");

  var color = Model.colorForStatus(status, { muted: "#60758C" });
  assert.strictEqual(color, "#60758C");

  var badge = Model.badgeInfo(status);
  assert.strictEqual(badge.text, isPt ? "DADOS DESATUALIZADOS" : "DATA STALE");
  assert.strictEqual(Model.badgeInfo(status, "en").text, "DATA STALE");
  assert.strictEqual(Model.badgeInfo(status, "pt").text, "DADOS DESATUALIZADOS");

  // Recovery test: if time is within 30s of update, should not be stale
  var freshNow = Date.parse("2026-10-27T20:30:25.000Z");
  var recoveredStatus = Model.resolveStatus(parsed.state, true, 0, freshNow);
  assert.strictEqual(recoveredStatus, "ok", "Fresh state recovers to 'ok'");
});

// 5. Corrupt or Truncated JSON Resilience (corrupt-json.json)
check("handles corrupt and truncated JSON gracefully without throwing", function() {
  var raw = loadFixture("corrupt-json.json");
  var parsed = Model.parseState(raw);
  assert.strictEqual(parsed.valid, false, "Corrupt JSON must be flagged invalid");
  assert.strictEqual(parsed.state, null);
  assert.ok(typeof parsed.error === "string");

  var status = Model.resolveStatus(parsed.state, parsed.valid);
  assert.strictEqual(status, "stopped", "Invalid state must resolve to 'stopped'");

  var tooltip = Model.tooltipFor(parsed.state, status);
  assert.strictEqual(tooltip, isPt ? "omarchy-doctor: Monitor Inativo" : "omarchy-doctor: Inactive Monitor");
  assert.strictEqual(Model.tooltipFor(parsed.state, status, "en"), "omarchy-doctor: Inactive Monitor");
  assert.strictEqual(Model.tooltipFor(parsed.state, status, "pt"), "omarchy-doctor: Monitor Inativo");

  var badge = Model.badgeInfo(status);
  assert.strictEqual(badge.text, isPt ? "MONITOR DESCONECTADO" : "MONITOR DISCONNECTED");
  assert.strictEqual(Model.badgeInfo(status, "en").text, "MONITOR DISCONNECTED");
  assert.strictEqual(Model.badgeInfo(status, "pt").text, "MONITOR DESCONECTADO");
});

// 6. Missing File / Null / Empty State Resilience
check("handles missing file, empty string or null gracefully", function() {
  var p1 = Model.parseState(null);
  assert.strictEqual(p1.valid, false);
  assert.strictEqual(Model.resolveStatus(p1.state, p1.valid), "stopped");

  var p2 = Model.parseState("");
  assert.strictEqual(p2.valid, false);
  assert.strictEqual(Model.resolveStatus(p2.state, p2.valid), "stopped");

  var p3 = Model.parseState("   ");
  assert.strictEqual(p3.valid, false);
  assert.strictEqual(Model.resolveStatus(p3.state, p3.valid), "stopped");
});

// 7. Daemon Inactive / Service Stopped Check
check("resolves to 'stopped' when service.active is false", function() {
  var raw = loadFixture("fixture-ok.json");
  var parsed = Model.parseState(raw);
  parsed.state.service.active = false;

  var testNow = Date.parse("2026-10-27T20:50:10.000Z");
  var status = Model.resolveStatus(parsed.state, true, 0, testNow);
  assert.strictEqual(status, "stopped", "Inactive daemon must resolve to 'stopped'");
});

// 8. SMART Hardware Health and Sudoers Authorization (fixture-smart-ok.json)
check("correctly parses authorized SMART devices and detects hardware failures", function() {
  var raw = loadFixture("fixture-smart-ok.json");
  var parsed = Model.parseState(raw);
  assert.strictEqual(parsed.valid, true);

  var summary = Model.smartStatusSummary(parsed.state.smart);
  assert.strictEqual(summary.available, true);
  assert.strictEqual(summary.ok, true);
  assert.ok(summary.text.indexOf("/dev/nvme0n1 (PASSED, 34°C)") !== -1);
  assert.ok(summary.text.indexOf("/dev/sda (PASSED, 31°C)") !== -1);
  assert.strictEqual(Model.smartStatusSummary(parsed.state.smart, "en").text,
    "Physical Disks: /dev/nvme0n1 (PASSED, 34°C) • /dev/sda (PASSED, 31°C)");
  assert.strictEqual(Model.smartStatusSummary(parsed.state.smart, "pt").text,
    "Discos Físicos: /dev/nvme0n1 (PASSED, 34°C) • /dev/sda (PASSED, 31°C)");

  // Test failing device elevation to critical
  var failingState = JSON.parse(raw);
  failingState.smart.devices[1].failing = true;
  failingState.smart.devices[1].health = "FAILING";
  var testNow = Date.parse("2026-10-27T20:50:10.000Z");
  var critStatus = Model.resolveStatus(failingState, true, 0, testNow);
  assert.strictEqual(critStatus, "critical", "Failing SMART device must elevate macro status to critical");

  var failingSummary = Model.smartStatusSummary(failingState.smart);
  assert.strictEqual(failingSummary.ok, false);
  assert.ok(failingSummary.text.indexOf("sda") !== -1);
  assert.strictEqual(Model.smartStatusSummary(failingState.smart, "en").text,
    "WARNING: Imminent physical failure on sda!");
  assert.strictEqual(Model.smartStatusSummary(failingState.smart, "pt").text,
    "ALERTA: Falha física iminente em sda!");
});

// 9. PSI (Pressure Stall Information) Graded Color & Thresholds
check("evaluates PSI values and returns proper graded colors", function() {
  var tokens = { dark_fg: "#91A4BB", yellow: "#D9B66A", dangerBase: "#E86A6A" };

  // Normal (< 15%)
  assert.strictEqual(Model.psiColor(0.4, tokens), "#91A4BB");
  assert.strictEqual(Model.psiColor(14.9, tokens), "#91A4BB");

  // Moderate (15% - 24.9%)
  assert.strictEqual(Model.psiColor(15.0, tokens), "#D9B66A");
  assert.strictEqual(Model.psiColor(24.5, tokens), "#D9B66A");

  // High / Critical (>= 25%)
  assert.strictEqual(Model.psiColor(25.0, tokens), "#E86A6A");
  assert.strictEqual(Model.psiColor(34.2, tokens), "#E86A6A");

  // Missing / NaN
  assert.strictEqual(Model.psiColor(null, tokens), "#91A4BB");
});

// 10. Byte & Percentage Formatters
check("formatBytes formats correctly across B, KiB, MiB, GiB, TiB", function() {
  assert.strictEqual(Model.formatBytes(null), "N/D");
  assert.strictEqual(Model.formatBytes(undefined), "N/D");
  assert.strictEqual(Model.formatBytes(0), "0 B");
  assert.strictEqual(Model.formatBytes(512), "512 B");
  assert.strictEqual(Model.formatBytes(1024), "1 KiB");
  assert.strictEqual(Model.formatBytes(1572864), "1.5 MiB");
  assert.strictEqual(Model.formatBytes(1932735283), "1.8 GiB");
  assert.strictEqual(Model.formatBytes(274877906944), "256 GiB");
});

check("formatPercent formats properly with fallback", function() {
  assert.strictEqual(Model.formatPercent(null), "N/D");
  assert.strictEqual(Model.formatPercent(55.0), "55%");
  assert.strictEqual(Model.formatPercent(1.23), "1.2%");
});

// 11. Relative Time Calculations
check("relativeTime returns human friendly relative strings", function() {
  var now = 1700000000000;
  assert.strictEqual(Model.relativeTime(null, now), "N/D");

  // Active locale check
  assert.strictEqual(Model.relativeTime(now - 2000, now), isPt ? "agora" : "now");
  assert.strictEqual(Model.relativeTime(now - 14000, now), isPt ? "há 14s" : "14s ago");
  assert.strictEqual(Model.relativeTime(now - 120000, now), isPt ? "há 2m" : "2m ago");
  assert.strictEqual(Model.relativeTime(now - 7200000, now), isPt ? "há 2h" : "2h ago");
  assert.strictEqual(Model.relativeTime(now - 86400000 * 3, now), isPt ? "há 3d" : "3d ago");

  // Explicit English check
  assert.strictEqual(Model.relativeTime(now - 2000, now, "en"), "now");
  assert.strictEqual(Model.relativeTime(now - 14000, now, "en"), "14s ago");
  assert.strictEqual(Model.relativeTime(now - 120000, now, "en"), "2m ago");
  assert.strictEqual(Model.relativeTime(now - 7200000, now, "en"), "2h ago");
  assert.strictEqual(Model.relativeTime(now - 86400000 * 3, now, "en"), "3d ago");

  // Explicit Portuguese check
  assert.strictEqual(Model.relativeTime(now - 2000, now, "pt"), "agora");
  assert.strictEqual(Model.relativeTime(now - 14000, now, "pt"), "há 14s");
  assert.strictEqual(Model.relativeTime(now - 120000, now, "pt"), "há 2m");
  assert.strictEqual(Model.relativeTime(now - 7200000, now, "pt"), "há 2h");
  assert.strictEqual(Model.relativeTime(now - 86400000 * 3, now, "pt"), "há 3d");

  // Fallback checks for null, C, en_US
  assert.strictEqual(Model.relativeTime(now - 14000, now, "C"), "14s ago");
  assert.strictEqual(Model.relativeTime(now - 14000, now, "en_US"), "14s ago");
});

// 12. Strict Icon Verification (Zero Emojis, 100% SVG Symbolic)
check("recentActionIcon returns clean freedesktop SVG names without emojis", function() {
  var pIcon = Model.recentActionIcon("pacman_cache");
  assert.strictEqual(pIcon, "application-x-executable-symbolic");
  assert.ok(!/[\u{1F300}-\u{1F9FF}]/u.test(pIcon), "Icon must not contain emojis");

  var dIcon = Model.recentActionIcon("docker_cache");
  assert.strictEqual(dIcon, "emblem-system-symbolic");
  assert.ok(!/[\u{1F300}-\u{1F9FF}]/u.test(dIcon), "Icon must not contain emojis");

  var jIcon = Model.recentActionIcon("systemd_journal");
  assert.strictEqual(jIcon, "preferences-desktop-appearance-symbolic");
  assert.ok(!/[\u{1F300}-\u{1F9FF}]/u.test(jIcon), "Icon must not contain emojis");
});

console.log("SUCCESS: All " + passed + " doctor model tests passed cleanly!");
