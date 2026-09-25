import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    required property var modelData
    property var workspaceModel: null

    property bool active: modelData.active === true
    property bool occupied: modelData.occupied === true
    property bool urgent: modelData.urgent === true
    property bool audio: modelData.audio === true
    property bool isEmpty: modelData.isEmpty === true

    width: active ? 48 : (isEmpty ? 36 : 40)
    height: 28

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: 14
        color: active ? Color.accent : (occupied ? Color.surfaceLight : "transparent")
        border.color: urgent ? "#FF6B6B" : (audio ? Color.accent : "transparent")
        border.width: (urgent || audio) ? 2 : 0

        Row {
            anchors.centerIn: parent
            spacing: 4

            Text {
                id: nameText
                text: modelData.name
                color: active ? Color.background : (occupied ? Color.text : Color.muted)
                font.pixelSize: 12
                font.weight: active ? Font.Medium : Font.Normal
            }

            Rectangle {
                id: audioBadge
                width: 6
                height: 6
                radius: 3
                color: Color.accent
                visible: audio && !active
            }

            Rectangle {
                id: urgentBadge
                width: 6
                height: 6
                radius: 3
                color: "#FF6B6B"
                visible: urgent && !audio
            }
        }
    }

    MouseArea {
        anchors.fill: pill
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: workspaceModel.focusWorkspace(modelData.id)
        onWheel: workspaceModel.scrollWorkspace(wheel.angleDelta.y > 0 ? -1 : 1)
        onEntered: pill.opacity = 0.8
        onExited: pill.opacity = 1.0
    }

    Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 150 } }
}