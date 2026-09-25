import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property string icon: ""
    property var bar: null
    property bool hovered: false

    width: 36
    height: 36
    signal clicked()

    Rectangle {
        id: bg
        anchors.centerIn: parent
        width: 32
        height: 32
        radius: 8
        color: hovered ? Color.surfaceLight : "transparent"
        border.color: "transparent"
        border.width: 0

        Image {
            anchors.centerIn: parent
            width: 18
            height: 18
            source: "image://theme/" + icon
            color: Color.text
            fillMode: Image.PreserveAspectFit
        }
    }

    MouseArea {
        anchors.fill: bg
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: hovered = true
        onExited: hovered = false
        onClicked: root.clicked()
        onWheel: root.wheel(wheel)
    }
}