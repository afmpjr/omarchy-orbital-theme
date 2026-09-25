import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property var bar: null
    property var dockModel: DockModel

    width: implicitWidth
    height: 44

    Component.onCompleted: {
        dockModel = DockModel
        dockModel.init(root)
    }

    Repeater {
        id: dockRepeater
        model: root.dockModel.items
        delegate: DockItem {
            required property var modelData
            bar: root.bar
            dockModel: root.dockModel
        }
    }

    // Drop area for pinning new apps
    DropArea {
        anchors.fill: parent
        keys: ["application/x-desktop"]
        onEntered: { root.dockModel.dragOver = true }
        onExited: { root.dockModel.dragOver = false }
        onDropped: {
            var mime = drop.mimeData
            if (mime.hasFormat("application/x-desktop")) {
                var desktopId = mime.data("application/x-desktop")
                root.dockModel.pinApp(desktopId)
            }
        }
    }
}