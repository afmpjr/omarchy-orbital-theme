// plugins/orbital.doctor/I18n.js
// Pure, Qt-free internationalization module for omarchy-doctor.
// Canonical default language: English ('en').
// Localized language: Portuguese / Brazil ('pt').

function detectLocale() {
  var lang = "";
  if (typeof Quickshell !== "undefined" && Quickshell.env) {
    lang = Quickshell.env("ORBITAL_LANG") || Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || "";
  } else if (typeof process !== "undefined" && process.env) {
    lang = process.env.ORBITAL_LANG || process.env.LC_ALL || process.env.LC_MESSAGES || process.env.LANG || "";
  } else if (typeof Qt !== "undefined" && Qt.locale) {
    lang = Qt.locale().name || "";
  }
  return String(lang).toLowerCase().startsWith("pt") ? "pt" : "en";
}

var pt = {
  // Status badges
  "SYSTEM HEALTHY": "SISTEMA SAUDÁVEL",
  "ATTENTION NEEDED": "ATENÇÃO NECESSÁRIA",
  "CRITICAL CONDITION": "CONDIÇÃO CRÍTICA",
  "DATA STALE": "DADOS DESATUALIZADOS",
  "MONITOR DISCONNECTED": "MONITOR DESCONECTADO",

  // Bar tooltips & summaries
  "omarchy-doctor: Healthy System": "omarchy-doctor: Sistema Saudável",
  "omarchy-doctor: Inactive Monitor": "omarchy-doctor: Monitor Inativo",
  "omarchy-doctor: Data Stale": "omarchy-doctor: Dados Desatualizados",
  "omarchy-doctor: Attention (%s)": "omarchy-doctor: Atenção (%s)",
  "omarchy-doctor: CRITICAL (%s)": "omarchy-doctor: CRÍTICO (%s)",
  "Attention needed": "Atenção necessária",
  "Critical condition": "Condição crítica",
  "Disk at %s": "Disco em %s",
  "%d failed unit(s)": "%d unit(s) em falha",

  // Sections & Headers
  "OMARCHY DOCTOR": "OMARCHY DOCTOR",
  "RESOURCES & PRESSURE": "RECURSOS & PRESSÃO",
  "Root Disk (/)": "Disco Raiz (/)",
  "RAM Memory": "Memória RAM",
  "System Pressure (PSI avg10)": "Pressão do Sistema (PSI avg10)",
  "I/O PSI": "I/O PSI",
  "CPU PSI": "CPU PSI",
  "RAM PSI": "RAM PSI",
  "zRAM: Inactive / Not configured": "zRAM: Inativo / Não configurado",
  "RECENT AUTOMATIC ACTIONS": "AÇÕES AUTOMÁTICAS RECENTES",
  "No auto-cleanup needed. Resources within parameters.": "Nenhuma auto-limpeza necessária. Recursos dentro dos parâmetros.",
  "Automatic maintenance": "Manutenção automática",
  "INTEGRITY & HARDWARE": "INTEGRIDADE & HARDWARE",
  "Last check: %s • %s": "Último check: %s • %s",
  "Daemon active (pid %s)": "Daemon ativo (pid %s)",
  "Daemon inactive": "Daemon inativo",

  // Action Buttons
  "Clean Now (Full Sanitization)": "Limpar Agora (Saneamento Completo)",
  "Cleaning Station in Background...": "Saneando Estação em Segundo Plano...",
  "Diagnose with AI": "Diagnosticar com IA",
  "Open Report": "Abrir Relatório",
  "Simulate Cleanup": "Simular Limpeza",

  // Systemd status
  "Systemd: 0 failed units (all operational)": "Systemd: 0 units em falha (todas operando)",
  "%d failed unit(s): %s": "%d unit(s) em falha: %s",
  "unknown unit": "unit desconhecida",
  "Click to inspect/resolve": "Clique para agir",

  // SMART status
  "Physical Disks: %s": "Discos Físicos: %s",
  "WARNING: Imminent physical failure on %s!": "ALERTA: Falha física iminente em %s!",
  "SMART: Requires root (permission pending)": "SMART: Requer root (autorização pendente)",
  "SMART: No devices detected": "SMART: Nenhum dispositivo detectado",
  "disk": "disco",

  // Relative clock
  "now": "agora",
  "just now": "agora",
  "%ss ago": "há %ss",
  "%sm ago": "há %sm",
  "%sh ago": "há %sh",
  "%sd ago": "há %sd",
  "N/D": "N/D"
};

function format(template, params) {
  if (params === undefined || params === null) return template;
  var args = Array.isArray(params) ? params : [params];
  var idx = 0;
  return String(template).replace(/%[sd]/g, function() {
    return idx < args.length ? String(args[idx++]) : "";
  });
}

function t(key, params, localeOverride) {
  var rawLoc = localeOverride || detectLocale();
  var loc = String(rawLoc).toLowerCase().startsWith("pt") ? "pt" : "en";
  var str = key;
  if (loc === "pt" && pt && typeof pt[key] === "string") {
    str = pt[key];
  }
  if (params !== undefined && params !== null) {
    return format(str, params);
  }
  return str;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    detectLocale: detectLocale,
    t: t,
    format: format,
    pt: pt
  };
}
