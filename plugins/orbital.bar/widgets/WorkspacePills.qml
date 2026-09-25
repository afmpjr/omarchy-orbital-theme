import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property var bar: null
    property var workspaceModel: WorkspaceModel

    width: implicitWidth
    height: 44

    Component.onCompleted: {
        workspaceModel = WorkspaceModel
        workspaceModel.init(root)
    }

    Repeater {
        id: pillsRepeater
        model: root.workspaceModel.pills
        delegate: WorkspacePill {
            required property var modelData
            workspaceModel: root.workspaceModel
        }
    }
}