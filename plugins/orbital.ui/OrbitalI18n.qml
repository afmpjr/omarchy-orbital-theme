pragma Singleton
// Interface language: English, or Portuguese (Brazil) when the system locale is pt*.
// ORBITAL_LANG=en|pt in the shell's environment overrides the locale (handy for testing).
// Use from a plugin:  import "../orbital.ui" as OrbitalUi  ...  OrbitalUi.OrbitalI18n.t("Cancel")
import Quickshell
import QtQuick
import "I18n.js" as Dict

QtObject {
  readonly property string lang: {
    var forced = String(Quickshell.env("ORBITAL_LANG") || "").toLowerCase()
    if (forced === "pt" || forced === "en") return forced
    return Qt.locale().name.toLowerCase().indexOf("pt") === 0 ? "pt" : "en"
  }
  readonly property bool pt: lang === "pt"

  function t(s) {
    if (!pt) return s
    var v = Dict.pt[s]
    return v === undefined ? s : v
  }
}
