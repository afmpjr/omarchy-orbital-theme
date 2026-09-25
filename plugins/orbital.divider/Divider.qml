// Orbital Divider — a thin hairline between two groups of bar widgets
// (mockup: one between the avatar and the pinned apps, one between the
// tray/system icons and the clock). Same idea as arc.dock's own
// `showSeparator`, as a standalone bar-widget rather than something
// baked into any one group, so it can sit anywhere in shell.json's
// layout array.

import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "orbital.divider"

  implicitWidth: root.vertical ? root.barSize : Style.space(9)
  implicitHeight: root.vertical ? Style.space(9) : root.barSize

  Rectangle {
    anchors.centerIn: parent
    width: root.vertical ? root.barSize * 0.5 : 1
    height: root.vertical ? 1 : root.barSize * 0.5
    color: root.bar ? root.bar.foreground : Color.foreground
    opacity: 0.18
  }
}
