import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
    id: root
    property var bar: null
    property string userName: Quickshell.env("USER") || "user"
    property string avatarPath: ""
    property bool menuOpen: false

    width: implicitWidth
    height: 44

    function getAvatarPath() {
        var home = Quickshell.env("HOME")
        var candidates = [
            home + "/.face",
            home + "/.face.icon",
            home + "/.config/omarchy/avatar.png",
            home + "/.config/omarchy/themes/orbital/avatar.png"
        ]
        for (var i = 0; i < candidates.length; i++) {
            if (File.exists(candidates[i])) return candidates[i]
        }
        return ""
    }

    Component.onCompleted: {
        avatarPath = getAvatarPath()
    }

    Rectangle {
        id: avatarBg
        width: 44
        height: 44
        radius: 22
        color: Color.accent
        border.color: Color.border
        border.width: 1
        clip: true

        Image {
            id: avatarImg
            anchors.fill: parent
            source: avatarPath ? "file://" + avatarPath : ""
            fillMode: Image.PreserveAspectCrop
            visible: avatarPath !== ""
        }

        Text {
            id: avatarInitial
            anchors.centerIn: parent
            text: userName.length > 0 ? userName[0].toUpperCase() : "?"
            color: Color.background
            font.pixelSize: 18
            font.weight: Font.Medium
            visible: avatarPath === ""
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                menuOpen = !menuOpen
                userMenu.popup()
            }
            onEntered: avatarBg.opacity = 0.8
            onExited: avatarBg.opacity = 1.0
        }
    }

    Menu {
        id: userMenu
        x: avatarBg.x
        y: avatarBg.y + avatarBg.height + 4
        transformOrigin: Menu.TopLeft

        MenuItem {
            text: "Configurações"
            icon.name: "preferences-system"
            onTriggered: {
                menuOpen = false
                if (root.bar && root.bar.shell) {
                    root.bar.shell.openMenu("settings")
                }
            }
        }

        MenuItem {
            text: "Bloquear"
            icon.name: "system-lock-screen"
            onTriggered: {
                menuOpen = false
                Quickshell.run("hyprctl dispatch exec hyprlock")
            }
        }

        MenuSeparator {}

        MenuItem {
            text: "Sair"
            icon.name: "system-log-out"
            onTriggered: {
                menuOpen = false
                Quickshell.run("hyprctl dispatch exit")
            }
        }

        onAboutToHide: menuOpen = false
    }
}