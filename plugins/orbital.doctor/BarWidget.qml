import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DoctorModel.js" as Model
import "../orbital.ui" as OrbitalUi

// BarWidget.qml — Compact bar indicator for omarchy-doctor in the Orbital theme.
// Adheres strictly to Orbital design tokens, pure vector SVGs, and zero-emoji policy.
BarWidget {
  id: root
  moduleName: "orbital.doctor"

  readonly property string statePath: {
    var xdg = Quickshell.env("XDG_STATE_HOME")
    if (xdg && xdg.length > 0) return xdg + "/omarchy-doctor/state.json"
    var home = Quickshell.env("HOME")
    return (home && home.length > 0 ? home : "/home") + "/.local/state/omarchy-doctor/state.json"
  }

  // Reactive state loaded from state.json
  property var doctorState: ({})
  property bool stateValid: false
  property double lastModifiedMs: 0

  // Time ticker to update staleness and relative timestamps every 5s
  property double nowTick: Date.now()
  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.nowTick = Date.now()
  }

  readonly property string status: Model.resolveStatus(doctorState, stateValid, lastModifiedMs, nowTick)

  // Panel integration contract (aligned with Bar.findPanelWidget and KeyboardPanel)
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item && typeof panelLoader.item.closeForPopoutSwitch === "function") {
      panelLoader.item.closeForPopoutSwitch()
    } else {
      root.close()
    }
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()

  // State file loading via Quickshell.Io.FileView
  FileView {
    id: stateFile
    path: root.statePath
    printErrors: false
    watchChanges: true

    onLoaded: {
      var raw = text()
      var parsed = Model.parseState(raw)
      root.stateValid = parsed.valid
      root.doctorState = parsed.valid && parsed.state ? parsed.state : ({})
      root.lastModifiedMs = Date.now()
    }

    onLoadFailed: {
      root.stateValid = false
      root.doctorState = ({})
    }
  }

  // Relaxed fallback timer to reload stateFile if daemon rotated inode via atomic replace
  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: stateFile.reload()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // IPC control verbs for scripting and shell actions
  IpcHandler {
    target: "orbital.doctor"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function reload(): void { stateFile.reload() }
  }

  OrbitalUi.OrbitalTokens { id: tokens }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: 32
    horizontalMargin: 7
    tooltipText: Model.tooltipFor(root.doctorState, root.status)
    onPressed: function(mouse) { root.togglePanel() }

    OrbitalUi.OrbitalIcon {
      id: icon
      anchors.centerIn: parent
      size: 18
      name: "emblem-system-symbolic"
      tint: root.bar ? root.bar.barForeground : tokens.text
      opacity: root.status === "stale" || root.status === "stopped" ? 0.45 : 1.0
    }

    // Diagnostics Status Dot Badge
    Rectangle {
      id: statusDot
      visible: root.status !== "ok"
      width: 8
      height: 8
      radius: 4
      color: Model.colorForStatus(root.status, tokens)
      anchors.top: parent.top
      anchors.topMargin: Math.max(0, Math.round((parent.height - icon.size) / 2 - 2))
      anchors.right: parent.right
      anchors.rightMargin: Math.max(0, Math.round((parent.width - icon.size) / 2 - 2))

      // Smooth opacity pulsation for critical states
      SequentialAnimation on opacity {
        running: root.status === "critical"
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 750; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1.0; duration: 750; easing.type: Easing.InOutQuad }
      }
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
}
