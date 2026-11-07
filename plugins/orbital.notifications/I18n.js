// plugins/orbital.notifications/I18n.js
// Pure, Qt-free internationalization module for orbital.notifications.
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
  // Header & actions
  "Notifications": "Notificações",
  "Clear all": "Limpar tudo",
  "Mark all as read": "Marcar todas como lidas",

  // Filters
  "All": "Todas",
  "Unread": "Não lidas",
  "Do Not Disturb: on": "Não perturbe: ativado",
  "Do Not Disturb: off": "Não perturbe: desativado",

  // Empty state
  "No notifications yet": "Nenhuma notificação ainda",
  "No unread notifications": "Nenhuma notificação não lida",

  // Item actions & accessibility
  "Mark as read": "Marcar como lida",
  "Mark as unread": "Marcar como não lida",
  "Clear": "Limpar",
  "Open": "Abrir",
  "Dismiss": "Descartar",

  // Relative clock units & words
  "now": "agora",
  "minute": "minuto",
  "minutes": "minutos",
  "hour": "hora",
  "hours": "horas",
  "day": "dia",
  "days": "dias",
  "week": "semana",
  "weeks": "semanas",
  "ago": "atrás"
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
