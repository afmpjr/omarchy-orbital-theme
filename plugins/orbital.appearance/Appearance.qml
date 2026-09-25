// Orbital Appearance — dedicated window opened from the account menu's
// "Appearance" row. Picks the theme color (accent + glass tint) through
// orbital-accent.py, which regenerates the Orbital theme from its pristine
// blue baseline. Same safe overlay shape as orbital.account (PanelWindow +
// exclusive keyboard focus), colors/radius from the shared theme tokens.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "../orbital.ui" as OrbitalUi

Item {
  id: root

  function tr(s) { return OrbitalUi.OrbitalI18n.t(s) }
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string currentName: "blue"
  property bool busy: false

  readonly property string script: "python3 " + Quickshell.env("HOME") + "/.config/omarchy/plugins/orbital.appearance/orbital-accent.py"

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(1)))
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.family

  readonly property var swatches: [
    { name: "blue", label: tr("Blue"), color: "#39A9FF" }, { name: "indigo", label: tr("Indigo"), color: "#3939FF" },
    { name: "purple", label: tr("Purple"), color: "#9539FF" }, { name: "lilac", label: tr("Lilac"), color: "#CE39FF" },
    { name: "magenta", label: tr("Magenta"), color: "#FF39EF" }, { name: "pink", label: tr("Pink"), color: "#FF39AC" },
    { name: "rose", label: tr("Rose"), color: "#FF395A" }, { name: "red", label: tr("Red"), color: "#FF3939" },
    { name: "orange", label: tr("Orange"), color: "#FF8C39" }, { name: "amber", label: tr("Amber"), color: "#FFC439" },
    { name: "lime", label: tr("Lime"), color: "#ACFF39" }, { name: "green", label: tr("Green"), color: "#39FF8C" },
    { name: "mint", label: tr("Mint"), color: "#39FFBD" }, { name: "teal", label: tr("Teal"), color: "#39FFEE" },
    { name: "cyan", label: tr("Cyan"), color: "#39DEFF" }, { name: "white", label: tr("White"), color: "#FFFFFF" },
    { name: "gray", label: tr("Gray"), color: "#9E9E9E" }, { name: "black", label: tr("Black"), color: "#0A0A0A" }
  ]

  function open(payloadJson) {
    currentProc.running = true
    root.opened = true
  }
  function close() { root.opened = false }
  function toggle(payloadJson) { if (root.opened) root.close(); else root.open(payloadJson) }

  function pick(name) {
    root.currentName = name
    root.busy = true
    applyProc.command = ["bash", "-c", root.script + " '" + name + "'"]
    applyProc.running = true
  }

  Process {
    id: currentProc
    command: ["bash", "-c", root.script + " current"]
    stdout: SplitParser { onRead: function(line) { root.currentName = line.trim() } }
  }
  Process {
    id: applyProc
    onExited: root.busy = false
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "orbital-appearance"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Item {
      anchors.fill: parent
      focus: !hexInput.activeFocus
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
      }
    }

    BorderSurface {
      id: card
      width: Style.space(400)
      height: Style.space(330)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: hexInput.focus = false }

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.space(12)

        Row {
          width: parent.width
          Column {
            width: parent.width - closeText.width
            spacing: Style.space(2)
            Text {
              text: tr("Appearance")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              text: root.busy ? tr("Applying…") : tr("Theme color — accent and glass tint")
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
          Text {
            id: closeText
            text: "Esc"
            color: root.foreground
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Grid {
          id: grid
          columns: 6
          columnSpacing: Style.space(8)
          rowSpacing: Style.space(10)
          readonly property real cell: (parent.width - columnSpacing * (columns - 1)) / columns

          Repeater {
            model: root.swatches

            Item {
              required property var modelData
              readonly property bool current: root.currentName === modelData.name
              width: grid.cell
              height: Style.space(52)

              Rectangle {
                id: dot
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(30)
                height: width
                radius: width / 2
                color: modelData.color
                border.width: parent.current ? 2 : 1
                border.color: parent.current ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                scale: swMouse.containsMouse ? 1.12 : 1
                Behavior on scale { NumberAnimation { duration: 100 } }
              }
              Text {
                anchors.top: dot.bottom
                anchors.topMargin: Style.space(4)
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.label
                color: root.foreground
                opacity: parent.current ? 1 : 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea {
                id: swMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pick(modelData.name)
              }
            }
          }
        }

        Item {
          width: parent.width
          height: 1
          Rectangle { anchors.fill: parent; color: root.foreground; opacity: 0.12 }
        }

        // Custom color: any #rrggbb; hue is taken from it.
        Row {
          spacing: Style.space(8)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: tr("Custom")
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Rectangle {
            width: Style.space(110)
            height: Style.space(28)
            radius: Style.space(6)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            border.width: 1
            border.color: hexInput.activeFocus ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
            TextInput {
              id: hexInput
              anchors.fill: parent
              anchors.margins: Style.space(6)
              verticalAlignment: TextInput.AlignVCenter
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              maximumLength: 7
              text: "#"
              selectByMouse: true
              onAccepted: if (/^#[0-9a-fA-F]{6}$/.test(text)) root.pick(text.toLowerCase())
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: tr("Enter to apply")
            color: root.foreground
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // Full theme switcher (wallpapers/other themes) stays one click away.
        Text {
          text: tr("Themes and wallpapers ›")
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.close(); Util.execDetached("omarchy-menu toggle theme") }
          }
        }
      }
    }
  }
}
