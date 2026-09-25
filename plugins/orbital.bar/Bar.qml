import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

PanelWindow {
    id: root
    property var barConfig: {}
    property var barWidgetRegistry: {}
    property var shell: null
    property var omarchyPath: Quickshell.env("OMARCHY_PATH")

    property real floatGap: barConfig.floatGap || 12
    property real cornerRadius: barConfig.cornerRadius || 16
    property string position: barConfig.position || "bottom"

    visible: true
    WlrLayershell.namespace: "orbital-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.anchorLeft: position === "left" || position === "right" ? false : true
    WlrLayershell.anchorRight: position === "left" || position === "right" ? false : true
    WlrLayershell.anchorTop: position === "top"
    WlrLayershell.anchorBottom: position === "bottom"
    WlrLayershell.exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
        id: background
        anchors.fill: parent
        color: "transparent"

        BorderSurface {
            id: barSurface
            anchors {
                left: parent.left; leftMargin: floatGap
                right: parent.right; rightMargin: floatGap
                top: position === "top" ? parent.top : undefined; topMargin: position === "top" ? floatGap : 0
                bottom: position === "bottom" ? parent.bottom : undefined; bottomMargin: position === "bottom" ? floatGap : 0
                verticalCenter: position === "left" || position === "right" ? parent.verticalCenter : undefined
            }
            height: position === "left" || position === "right" ? parent.height - floatGap * 2 : 44
            width: position === "left" || position === "right" ? 44 : parent.width - floatGap * 2
            radius: cornerRadius
            color: Color.surface
            opacity: 0.85
            borderSpec: Border.surfaceSpec("menu", "border", Color.border, 1)
            padding: 8

            Row {
                id: contentRow
                anchors.fill: parent
                spacing: 8

                // LEFT SECTION: Avatar + Dock
                Item {
                    id: leftSection
                    width: implicitWidth
                    height: parent.height
                    Row {
                        anchors.fill: parent
                        spacing: 4

                        // Avatar Widget
                        Component {
                            id: avatarComponent
                            Item {
                                id: avatarRoot
                                property var bar: root
                                property string userName: Quickshell.env("USER") || "user"
                                property string avatarPath: ""

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

                                width: implicitWidth
                                height: 44

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
                        }

                        // Dock Section
                        Component {
                            id: dockSectionComponent
                            Item {
                                id: dockSectionRoot
                                property var bar: root
                                property var dockModel: DockModel

                                width: implicitWidth
                                height: 44

                                Repeater {
                                    id: dockRepeater
                                    model: dockSectionRoot.dockModel.items
                                    delegate: DockItem {
                                        required property var modelData
                                        bar: dockSectionRoot.bar
                                        dockModel: dockSectionRoot.dockModel
                                    }
                                }

                                DropArea {
                                    anchors.fill: parent
                                    keys: ["application/x-desktop"]
                                    onEntered: { dockSectionRoot.dockModel.dragOver = true }
                                    onExited: { dockSectionRoot.dockModel.dragOver = false }
                                    onDropped: {
                                        var mime = drop.mimeData
                                        if (mime.hasFormat("application/x-desktop")) {
                                            var desktopId = mime.data("application/x-desktop")
                                            dockSectionRoot.dockModel.pinApp(desktopId)
                                        }
                                    }
                                }
                            }
                        }

                        Loader {
                            sourceComponent: avatarComponent
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Loader {
                            sourceComponent: dockSectionComponent
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // CENTER SECTION: Workspace Pills
                Item {
                    id: centerSection
                    width: implicitWidth
                    height: parent.height
                    Loader {
                        sourceComponent: workspacePillsComponent
                    }
                }

                // RIGHT SECTION: System Controls + Clock
                Item {
                    id: rightSection
                    width: implicitWidth
                    height: parent.height
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        // System Control Buttons (4: Audio, Network, Bluetooth, Power)
                        Component {
                            id: systemControlButtonComponent
                            Item {
                                id: sysBtnRoot
                                property string icon: ""
                                property var bar: root
                                property bool hovered: false
                                signal clicked()

                                width: 36
                                height: 36

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
                        }

                        Loader {
                            sourceComponent: systemControlButtonComponent
                        }

                        Loader {
                            sourceComponent: systemControlButtonComponent
                        }

                        Loader {
                            sourceComponent: systemControlButtonComponent
                        }

                        Loader {
                            sourceComponent: systemControlButtonComponent
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        if (shell) {
            shell.registerBar(root)
        }
    }
}