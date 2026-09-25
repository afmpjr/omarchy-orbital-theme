// Orbital UI contract, part 2: the modal dialog.
//
// A full-screen dim layer plus one centred card, built only from
// OrbitalTokens. Callers describe *what* to show; they never style it.
//
// Properties (input)
//   opened          bool     visible when true
//   title           string   bold headline
//   glyph           string   optional Nerd Font glyph before the title
//   tone            string   "neutral" | "danger" — card outline + glyph color
//   message         string   optional muted paragraph under the title
//   rows            var      [{ label, value, tone? }] key/value details
//   buttons         var      [{ id, label, role }], role: neutral|primary|danger
//   defaultButton   int      button focused on open (index into buttons)
//   layerNamespace  string   Wayland layer namespace
//
// Signals (output)
//   activated(string id)   a button was chosen (click or Enter)
//   dismissed()            Esc or click outside the card
//
// The dialog never closes itself or runs commands: the owner reacts to the
// signals and flips `opened`. Keyboard: Esc dismisses, Left/Right/Tab cycle
// buttons, Enter activates. Popup shape matches the other Orbital overlays
// (PanelWindow + static WlrKeyboardFocus.Exclusive, visible: opened).

import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  property bool opened: false
  property string title: ""
  property string glyph: ""
  property string tone: "neutral"
  property string message: ""
  property var rows: []
  property var buttons: []
  property int defaultButton: 0
  property string layerNamespace: "orbital-dialog"

  property int focusedIndex: 0

  signal activated(string id)
  signal dismissed()

  OrbitalTokens { id: tk }

  readonly property bool danger: root.tone === "danger"
  readonly property int labelWidth: Style.space(78)

  onOpenedChanged: {
    if (opened) {
      root.focusedIndex = root.defaultButton
      Qt.callLater(function() { keys.forceActiveFocus() })
    }
  }

  function activate(index) {
    var b = root.buttons[index]
    if (b) root.activated(String(b.id))
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: root.layerNamespace
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: tk.dim }

    MouseArea { anchors.fill: parent; onClicked: root.dismissed() }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: Math.min(tk.cardWidth, panel.width - Style.gapsOut * 2)
      height: column.implicitHeight + tk.padding * 2
      radius: tk.cardRadius
      color: tk.surface
      border.width: 1
      border.color: root.danger ? tk.tone("danger", false).border : tk.outline

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var n = root.buttons.length
          if (event.key === Qt.Key_Escape) {
            root.dismissed()
            event.accepted = true
          } else if (n > 0 && (event.key === Qt.Key_Right || event.key === Qt.Key_Tab)) {
            root.focusedIndex = (root.focusedIndex + 1) % n
            event.accepted = true
          } else if (n > 0 && (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab)) {
            root.focusedIndex = (root.focusedIndex + n - 1) % n
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate(root.focusedIndex)
            event.accepted = true
          }
        }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: tk.padding
        spacing: tk.spacing

        Row {
          spacing: Style.space(8)
          visible: root.title !== ""

          Text {
            visible: root.glyph !== ""
            textFormat: Text.PlainText
            text: root.glyph
            color: root.danger ? tk.dangerText : tk.accent
            font.family: tk.fontFamily
            font.pixelSize: tk.titleSize
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            textFormat: Text.PlainText
            text: root.title
            width: column.width - (root.glyph !== "" ? Style.space(26) : 0)
            elide: Text.ElideRight
            color: tk.text
            font.family: tk.fontFamily
            font.pixelSize: tk.titleSize
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          visible: root.message !== ""
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.message
          color: tk.text
          opacity: tk.mutedOpacity
          font.family: tk.fontFamily
          font.pixelSize: tk.bodySize
        }

        Item { width: 1; height: Style.space(4); visible: root.rows.length > 0 }

        Repeater {
          model: root.rows

          Row {
            required property var modelData
            width: column.width
            spacing: Style.space(10)

            Text {
              width: root.labelWidth
              textFormat: Text.PlainText
              text: String(modelData.label || "")
              color: tk.text
              opacity: tk.mutedOpacity
              font.family: tk.fontFamily
              font.pixelSize: tk.bodySize
            }

            Text {
              width: column.width - root.labelWidth - parent.spacing
              textFormat: Text.PlainText
              text: String(modelData.value || "")
              color: modelData.tone === "danger" ? tk.dangerText : tk.text
              font.family: tk.fontFamily
              font.pixelSize: tk.bodySize
              wrapMode: Text.WrapAnywhere
            }
          }
        }

        Item { width: 1; height: Style.space(10) }

        Row {
          anchors.right: parent.right
          spacing: Style.space(10)

          Repeater {
            model: root.buttons

            Rectangle {
              required property int index
              required property var modelData

              readonly property var look: tk.tone(String(modelData.role || "neutral"), mouse.containsMouse)

              width: Math.max(tk.controlMinWidth, label.implicitWidth + Style.space(28))
              height: tk.controlHeight
              radius: tk.controlRadius
              color: look.fill
              border.width: 1
              border.color: root.focusedIndex === index ? tk.accent : look.border

              Text {
                id: label
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: String(modelData.label || "")
                color: look.text
                font.family: tk.fontFamily
                font.pixelSize: tk.bodySize
              }

              MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.focusedIndex = index
                onClicked: root.activate(index)
              }
            }
          }
        }
      }
    }
  }
}
