import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property var bar: null
    property string timeFormat: "ddd, MMM d HH:mm"
    property bool showCalendar: true

    width: implicitWidth
    height: 44

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: timeText.text = Qt.formatDateTime(new Date(), timeFormat)
    }

    Text {
        id: timeText
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 12
        text: Qt.formatDateTime(new Date(), timeFormat)
        color: Color.text
        font.pixelSize: 13
        font.weight: Font.Normal
    }

    MouseArea {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.bar && root.bar.shell && showCalendar) {
                root.bar.shell.openPanel("calendar")
            }
        }
        onEntered: timeText.color = Color.accent
        onExited: timeText.color = Color.text
    }
}