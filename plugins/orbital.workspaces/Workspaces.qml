import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  // Lowest-numbered id above every existing one, or 0 when 10 is reached.
  function nextWorkspaceId() {
    var ids = root.workspaceIds()
    var next = ids[ids.length - 1] + 1
    return next <= 10 ? next : 0
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length + (root.nextWorkspaceId() > 0 ? 1 : 0)
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      // Wrapped (not a bare WidgetButton): WidgetButton stays the real
      // click target (registerClickTarget/showTooltip keep working), drawn
      // label-less; the mockup's rounded-square chip with the workspace
      // NUMBER inside (not just a dot) is painted on top of it.
      Item {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        implicitWidth: button.implicitWidth
        implicitHeight: button.implicitHeight

        WidgetButton {
          id: button
          bar: root.bar
          text: ""
          labelVisible: false
          hasVisualContent: true
          fixedWidth: root.vertical ? root.barSize : Style.space(32)
          fixedHeight: root.barSize
          onPressed: function() { root.focusWorkspace(parent.modelData) }
        }

        Rectangle {
          id: chip
          anchors.centerIn: parent
          width: Style.space(26)
          height: Style.space(26)
          radius: Style.space(8)
          color: parent.focused
            ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
            : Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, parent.occupied ? 0.10 : 0.04)
          border.width: parent.focused ? 1 : 0
          border.color: Color.accent

          Behavior on color { ColorAnimation { duration: 120 } }

          Text {
            anchors.centerIn: parent
            text: modelData === 10 ? "0" : String(modelData)
            textFormat: Text.PlainText
            color: parent.parent.focused ? Color.accent : button.foreground
            opacity: parent.parent.focused || parent.parent.occupied ? 1 : 0.5
            font.family: button.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: parent.parent.focused
          }
        }
      }
    }

    // "+" — jump to the next workspace number that doesn't exist yet
    // (real behaviour: Hyprland creates the workspace on focus).
    Item {
      visible: root.nextWorkspaceId() > 0
      implicitWidth: plusButton.implicitWidth
      implicitHeight: plusButton.implicitHeight

      WidgetButton {
        id: plusButton
        bar: root.bar
        text: ""
        labelVisible: false
        hasVisualContent: true
        fixedWidth: root.vertical ? root.barSize : Style.space(32)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(root.nextWorkspaceId()) }
      }

      Text {
        anchors.centerIn: parent
        text: "+"
        textFormat: Text.PlainText
        color: plusButton.foreground
        opacity: 0.6
        font.family: plusButton.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
