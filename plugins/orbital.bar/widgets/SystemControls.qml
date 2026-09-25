import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property var bar: null

    width: implicitWidth
    height: 44

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        // Audio
        SystemControlButton {
            id: audioBtn
            icon: "audio-volume-high"
            bar: root.bar
            onClicked: {
                if (root.bar && root.bar.shell) {
                    root.bar.shell.openPanel("audio")
                }
            }
            onWheel: {
                var delta = wheel.angleDelta.y > 0 ? 5 : -5
                Quickshell.run("wpctl set-volume @DEFAULT_AUDIO_SINK@ " + delta + "%")
            }
        }

        // Network
        SystemControlButton {
            id: networkBtn
            icon: "network-wireless"
            bar: root.bar
            onClicked: {
                if (root.bar && root.bar.shell) {
                    root.bar.shell.openPanel("network")
                }
            }
        }

        // Bluetooth
        SystemControlButton {
            id: bluetoothBtn
            icon: "bluetooth"
            bar: root.bar
            onClicked: {
                if (root.bar && root.bar.shell) {
                    root.bar.shell.openPanel("bluetooth")
                }
            }
        }

        // Power
        SystemControlButton {
            id: powerBtn
            icon: "battery"
            bar: root.bar
            onClicked: {
                if (root.bar && root.bar.shell) {
                    root.bar.shell.openMenu("power")
                }
            }
        }
    }
}