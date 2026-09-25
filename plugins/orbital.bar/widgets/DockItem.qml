import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    required property var modelData
    property var bar: null
    property var dockModel: null
    property bool hovered: false
    property bool pressed: false

    width: 44
    height: 44

    property bool isRunning: modelData.running === true
    property bool isPinned: modelData.pinned === true
    property int windowCount: modelData.windowCount || 0

    Rectangle {
        id: bg
        anchors.centerIn: parent
        width: 36
        height: 36
        radius: 10
        color: hovered ? Color.accent + "33" : "transparent"
        border.color: pressed ? Color.accent : "transparent"
        border.width: pressed ? 2 : 0

        Image {
            id: icon
            anchors.centerIn: parent
            width: 24
            height: 24
            source: modelData.icon ? "image://theme/" + modelData.icon : ""
            fillMode: Image.PreserveAspectFit
            color: Color.text
            visible: modelData.icon !== ""
        }

        Text {
            id: fallbackText
            anchors.centerIn: parent
            text: modelData.name ? modelData.name[0].toUpperCase() : "?"
            color: Color.text
            font.pixelSize: 14
            font.weight: Font.Medium
            visible: !modelData.icon
        }

        // Running indicator dots
        Row {
            id: indicators
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            visible: isRunning && windowCount > 0

            Repeater {
                model: Math.min(windowCount, 4)
                delegate: Rectangle {
                    width: windowCount <= 4 ? 5 : 4
                    height: windowCount <= 4 ? 5 : 4
                    radius: 2
                    color: index === 0 ? Color.accent : Color.muted
                }
            }

            Rectangle {
                visible: windowCount > 4
                width: 12
                height: 4
                radius: 2
                color: Color.muted
                Text {
                    anchors.centerIn: parent
                    text: "+" + (windowCount - 4)
                    color: Color.text
                    font.pixelSize: 6
                }
            }
        }
    }

    MouseArea {
        id: clickArea
        anchors.fill: bg
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: hovered = true
        onExited: hovered = false
        onPressed: pressed = true
        onReleased: {
            pressed = false
            if (containsMouse) {
                if (modelData.running && modelData.windowCount > 0) {
                    dockModel.focusOrMinimize(modelData.appId, modelData.windowCount)
                } else {
                    dockModel.launchApp(modelData.appId)
                }
            }
        }
        onCanceled: pressed = false
    }

    // Right-click context menu
    MouseArea {
        anchors.fill: bg
        acceptedButtons: Qt.RightButton
        onClicked: {
            contextMenu.popup()
        }
    }

    Menu {
        id: contextMenu
        transformOrigin: Menu.TopLeft

        MenuItem {
            text: modelData.running ? "Nova janela" : "Abrir"
            onTriggered: dockModel.launchApp(modelData.appId)
        }

        if (modelData.running) {
            MenuItem {
                text: "Fechar todas as janelas"
                onTriggered: {
                    if (Hyprland && Hyprland.toplevels) {
                        var toplevels = Hyprland.toplevels
                        for (var i = 0; i < toplevels.length; i++) {
                            var t = toplevels[i]
                            if ((t.appId || t.class || "").toLowerCase() === modelData.appId.toLowerCase()) {
                                Hyprland.message("dispatch closewindow address:" + t.address)
                            }
                        }
                    }
                }
            }
        }

        if (modelData.pinned) {
            MenuItem {
                text: "Desfixar"
                onTriggered: {
                    var idx = root.dockModel._pinnedApps.findIndex(function(p) { return p.appId === modelData.appId })
                    if (idx >= 0) root.dockModel.unpinApp(idx)
                }
            }
        } else {
            MenuItem {
                text: "Fixar no dock"
                onTriggered: root.dockModel.pinApp(modelData.appId)
            }
        }
    }

    // Drag to reorder
    Drag.active: dragArea.drag.active
    Drag.dragType: Drag.Automatic
    Drag.onDragStarted: {
        root.dockModel.dragOver = true
    }
    Drag.onDragFinished: {
        root.dockModel.dragOver = false
    }

    DragArea {
        id: dragArea
        anchors.fill: bg
        dragType: Drag.Automatic
        onDragStarted: {
            drag.mimeData.setData("application/x-dock-item", JSON.stringify({index: modelData.index, appId: modelData.appId}))
            drag.supportedActions = Qt.MoveAction
        }
    }

    DropArea {
        anchors.fill: bg
        keys: ["application/x-dock-item"]
        onEntered: bg.color = Color.accent + "44"
        onExited: bg.color = hovered ? Color.accent + "33" : "transparent"
        onDropped: {
            var data = null
            try { data = JSON.parse(drop.mimeData.getData("application/x-dock-item")) } catch (e) { return }
            if (data && data.index !== modelData.index) {
                root.dockModel.reorderPinned(data.index, modelData.index)
            }
        }
    }
}