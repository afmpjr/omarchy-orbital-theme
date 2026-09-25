// Orbital UI contract, part 1: design tokens.
//
// Every value is derived from the active Orbital theme (Color.menu.*,
// Color.accent, Style.*), so accent and glass tint follow orbital.appearance
// and no plugin hardcodes a palette. Tones are the only fixed colors: "danger"
// is the red Orbital uses for destructive/crash surfaces.
//
// Consumers ask for a tone by name and get { text, fill, border }, so a
// component never decides colors itself:
//
//   neutral  quiet surface button / ordinary text
//   primary  the suggested action, tinted with the theme accent
//   danger   destructive or crash state
//
// See README.md for the dialog contract that builds on these.

import QtQuick
import qs.Commons

QtObject {
  id: tk

  // Surfaces
  readonly property color text: Color.menu.text
  readonly property color accent: Color.accent
  readonly property color surface: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 0.96)
  readonly property color dim: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 0.55)
  readonly property color outline: alpha(text, 0.18)

  // Metrics
  readonly property int cardRadius: Style.cornerRadius
  readonly property int controlRadius: Style.space(8)
  readonly property int controlHeight: Style.space(34)
  readonly property int controlMinWidth: Style.space(96)
  readonly property int cardWidth: Style.space(340)
  readonly property int padding: Style.space(18)
  readonly property int spacing: Style.space(6)

  // Type
  readonly property string fontFamily: Style.font.family
  readonly property int titleSize: Style.font.body
  readonly property int bodySize: Style.font.bodySmall
  readonly property real mutedOpacity: 0.6

  // Danger red (same tones as the launcher's destructive action).
  readonly property color dangerText: "#ff8f8f"
  readonly property color dangerBase: Qt.rgba(1, 0.42, 0.42, 1)

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // tone: "neutral" | "primary" | "danger"; hovered raises the fill.
  function tone(name, hovered) {
    if (name === "danger")
      return { text: dangerText, fill: alpha(dangerBase, hovered ? 0.30 : 0.18), border: alpha(dangerBase, 0.55) }
    if (name === "primary")
      return { text: text, fill: alpha(accent, hovered ? 0.26 : 0.16), border: alpha(accent, 0.55) }
    return { text: text, fill: alpha(text, hovered ? 0.10 : 0.05), border: outline }
  }
}
