import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DoctorModel.js" as Model
import "I18n.js" as I18n
import "../orbital.ui" as OrbitalUi

// Panel.qml — Diagnostics flyout popup for omarchy-doctor in the Orbital theme.
// Built on KeyboardPanel (Quattro / Quickshell), strictly adhering to Orbital tokens,
// zero emojis, safe terminal-only execution, and keyboard accessibility.
Panel {
  id: root
  moduleName: "orbital.doctor"
  ipcTarget: "orbital.doctor"
  manageIpc: false
  Component.onCompleted: Model.setI18n(I18n)

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var doctorState: hostWidget ? hostWidget.doctorState : ({})
  readonly property string status: hostWidget ? hostWidget.status : "stopped"

  // Local ticker for live relative timestamps inside the popup
  property double panelNow: Date.now()
  Timer {
    interval: 3000
    running: root.opened
    repeat: true
    onTriggered: root.panelNow = Date.now()
  }

  function open() {
    root.panelNow = Date.now()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  // Safe terminal command execution (TTY required, zero direct UI cleanups)
  function runTerminalCommand(commandString) {
    root.close()
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-launch-floating-terminal-with-presentation " + commandString)
    } else {
      runnerProc.command = ["foot", "-e", "bash", "-c", commandString]
      runnerProc.running = false
      runnerProc.running = true
    }
  }

  Process {
    id: runnerProc
    command: []
  }

  property bool isSanitizing: false

  Process {
    id: sanitizerProc
    command: ["/mnt/dados/projects/omarchy-orbital-theme/scripts/sanitize-station.sh"]
    onStarted: {
      root.isSanitizing = true
    }
    onExited: function(exitCode, exitStatus) {
      root.isSanitizing = false
      if (root.hostWidget && typeof root.hostWidget.reload === "function") {
        root.hostWidget.reload()
      }
    }
  }

  function startBackgroundSanitization() {
    if (root.isSanitizing) return
    root.isSanitizing = true
    sanitizerProc.running = false
    sanitizerProc.running = true
  }

  OrbitalUi.OrbitalTokens { id: tokens }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher

    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(Math.min(Style.space(700), scrollColumn.implicitHeight + tokens.padding * 2))

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: function(event) {
        root.close()
        event.accepted = true
      }

      Flickable {
        id: flickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: scrollColumn.implicitHeight + tokens.padding * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: scrollColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: tokens.padding
          spacing: Style.space(14)

          // -------------------------------------------------------------
          // Bloco 1: Header com Veredito Global & Relógio Relativo
          // -------------------------------------------------------------
          Row {
            id: headerRow
            width: parent.width
            height: Style.space(38)
            spacing: Style.space(10)

            OrbitalUi.OrbitalIcon {
              id: headerIcon
              size: 24
              name: "emblem-system-symbolic"
              tint: tokens.accent
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: headerTitles
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - headerIcon.width - statusPill.width - Style.space(20)
              spacing: Style.space(2)

              Text {
                text: "OMARCHY DOCTOR"
                color: "#FFFFFF"
                font.family: tokens.fontFamily
                font.pixelSize: 13
                font.bold: true
              }

              Text {
                text: {
                  var updated = root.doctorState ? root.doctorState.updated_at : null
                  var rel = Model.relativeTime(updated, root.panelNow)
                  var daemon = (root.doctorState && root.doctorState.service && root.doctorState.service.active)
                    ? I18n.t("Daemon active (pid %s)", [root.doctorState.service.pid])
                    : I18n.t("Daemon inactive")
                  return I18n.t("Last check: %s • %s", [rel, daemon])
                }
                color: "#91A4BB"
                font.family: tokens.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
                width: parent.width
              }
            }

            // Status Pill Tag
            Rectangle {
              id: statusPill
              anchors.verticalCenter: parent.verticalCenter
              height: Style.space(24)
              radius: Style.space(12)
              width: pillRow.implicitWidth + Style.space(16)

              readonly property var badge: Model.badgeInfo(root.status)
              readonly property color badgeColor: Model.colorForStatus(root.status, tokens)

              color: Qt.rgba(badgeColor.r, badgeColor.g, badgeColor.b, 0.16)
              border.color: Qt.rgba(badgeColor.r, badgeColor.g, badgeColor.b, 0.45)
              border.width: 1

              Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Style.space(6)

                Rectangle {
                  width: 6
                  height: 6
                  radius: 3
                  color: statusPill.badgeColor
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: statusPill.badge.text
                  color: statusPill.badgeColor
                  font.family: tokens.fontFamily
                  font.pixelSize: 10
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(255, 255, 255, 0.08)
          }

          // -------------------------------------------------------------
          // Bloco 2: Recursos Principais (Disco, Memória, zRAM) & PSI
          // -------------------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(10)

            Text {
              text: I18n.t("RESOURCES & PRESSURE")
              color: "#60758C"
              font.family: tokens.fontFamily
              font.pixelSize: 11
              font.bold: true
              font.letterSpacing: 0.5
            }

            // Disk Section (Clickable: Opens Full Storage Inspection)
            Rectangle {
              id: diskSectionBox
              width: parent.width
              height: Style.space(38)
              radius: Style.space(6)
              color: mouseDisk.containsMouse ? Qt.rgba(255, 255, 255, 0.05) : "transparent"
              border.color: mouseDisk.containsMouse ? Qt.rgba(255, 255, 255, 0.16) : "transparent"
              border.width: 1

              readonly property var diskData: (root.doctorState && root.doctorState.metrics && root.doctorState.metrics.disk)
                ? root.doctorState.metrics.disk : null
              readonly property real diskPct: diskData && typeof diskData.percent_used === "number" ? diskData.percent_used : 0

              MouseArea {
                id: mouseDisk
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runTerminalCommand("omarchy-doctor scan --full")
              }

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(4)
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  height: 18

                  Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Text {
                      text: I18n.t("Root Disk (/)")
                      color: mouseDisk.containsMouse ? "#FFFFFF" : "#F4F8FF"
                      font.family: tokens.fontFamily
                      font.pixelSize: 12
                      font.bold: mouseDisk.containsMouse
                    }

                    OrbitalUi.OrbitalIcon {
                      size: 12
                      name: "view-more-symbolic"
                      tint: mouseDisk.containsMouse ? "#39A9FF" : Qt.rgba(255, 255, 255, 0.25)
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                      if (!diskSectionBox.diskData) return "N/D"
                      var used = Model.formatBytes(diskSectionBox.diskData.used_bytes)
                      var tot = Model.formatBytes(diskSectionBox.diskData.total_bytes)
                      var pct = Model.formatPercent(diskSectionBox.diskPct)
                      return used + " / " + tot + " (" + pct + ")"
                    }
                    color: mouseDisk.containsMouse ? "#FFFFFF" : "#91A4BB"
                    font.family: "JetBrainsMono Nerd Font, monospace"
                    font.pixelSize: 11
                  }
                }

                // Disk Progress Track
                Rectangle {
                  width: parent.width
                  height: 6
                  radius: 3
                  color: Qt.rgba(255, 255, 255, 0.08)

                  Rectangle {
                    height: parent.height
                    radius: 3
                    width: Math.min(parent.width, Math.max(0, parent.width * (diskSectionBox.diskPct / 100.0)))
                    color: Model.diskColor(diskSectionBox.diskPct, tokens)
                  }
                }
              }
            }

            // RAM and zRAM Section
            Column {
              width: parent.width
              spacing: Style.space(4)

              readonly property var memData: (root.doctorState && root.doctorState.metrics && root.doctorState.metrics.memory)
                ? root.doctorState.metrics.memory : null
              readonly property real memPct: memData && typeof memData.percent_used === "number" ? memData.percent_used : 0

              readonly property var zramData: (root.doctorState && root.doctorState.metrics && root.doctorState.metrics.zram)
                ? root.doctorState.metrics.zram : null

              Item {
                width: parent.width
                height: 18

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: I18n.t("RAM Memory")
                  color: "#F4F8FF"
                  font.family: tokens.fontFamily
                  font.pixelSize: 12
                }
                Text {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: {
                    if (!parent.parent.memData) return "N/D"
                    var used = Model.formatBytes(parent.parent.memData.used || parent.parent.memData.used_bytes)
                    var tot = Model.formatBytes(parent.parent.memData.total || parent.parent.memData.total_bytes)
                    var pct = Model.formatPercent(parent.parent.memPct)
                    return used + " / " + tot + " (" + pct + ")"
                  }
                  color: "#91A4BB"
                  font.family: "JetBrainsMono Nerd Font, monospace"
                  font.pixelSize: 11
                }
              }

              // RAM Progress Track
              Rectangle {
                width: parent.width
                height: 6
                radius: 3
                color: Qt.rgba(255, 255, 255, 0.08)

                Rectangle {
                  height: parent.height
                  radius: 3
                  width: Math.min(parent.width, Math.max(0, parent.width * (parent.parent.memPct / 100.0)))
                  color: "#5BC0FF"
                }
              }

              // zRAM Subline
              Text {
                text: {
                  if (!parent.zramData) return I18n.t("zRAM: Inactive / Not configured")
                  var zUsed = Model.formatBytes(parent.zramData.used || parent.zramData.used_bytes)
                  var zTot = Model.formatBytes(parent.zramData.total || parent.zramData.total_bytes)
                  var zPct = Model.formatPercent(parent.zramData.percent_used)
                  return "zRAM: " + zUsed + " / " + zTot + " (" + zPct + ")"
                }
                color: "#60758C"
                font.family: tokens.fontFamily
                font.pixelSize: 11
              }
            }

            // PSI (Pressure Stall Information - 10s Kernel Avg)
            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: I18n.t("System Pressure (PSI avg10)")
                color: "#91A4BB"
                font.family: tokens.fontFamily
                font.pixelSize: 11
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                readonly property var psiData: (root.doctorState && root.doctorState.metrics && root.doctorState.metrics.psi)
                  ? root.doctorState.metrics.psi : null

                // I/O Pressure Chip
                Rectangle {
                  width: (parent.width - Style.space(12)) / 3
                  height: Style.space(34)
                  radius: Style.space(6)
                  color: Qt.rgba(255, 255, 255, 0.04)
                  border.color: Qt.rgba(255, 255, 255, 0.08)

                  readonly property real ioVal: {
                    if (!parent.psiData || !parent.psiData.io) return 0
                    if (parent.psiData.io.some && typeof parent.psiData.io.some.avg10 === "number") return parent.psiData.io.some.avg10
                    if (typeof parent.psiData.io.some_avg10 === "number") return parent.psiData.io.some_avg10
                    return 0
                  }
                  readonly property color chipColor: Model.psiColor(ioVal, tokens)

                  Column {
                    anchors.centerIn: parent
                    spacing: 1
                    Text {
                      text: I18n.t("I/O PSI")
                      color: "#60758C"
                      font.pixelSize: 9
                      font.bold: true
                      anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                      text: Model.formatPercent(parent.parent.ioVal)
                      color: parent.parent.chipColor
                      font.family: "JetBrainsMono Nerd Font, monospace"
                      font.pixelSize: 11
                      font.bold: true
                      anchors.horizontalCenter: parent.horizontalCenter
                    }
                  }
                }

                // CPU Pressure Chip
                Rectangle {
                  width: (parent.width - Style.space(12)) / 3
                  height: Style.space(34)
                  radius: Style.space(6)
                  color: Qt.rgba(255, 255, 255, 0.04)
                  border.color: Qt.rgba(255, 255, 255, 0.08)

                  readonly property real cpuVal: {
                    if (!parent.psiData || !parent.psiData.cpu) return 0
                    if (parent.psiData.cpu.some && typeof parent.psiData.cpu.some.avg10 === "number") return parent.psiData.cpu.some.avg10
                    if (typeof parent.psiData.cpu.some_avg10 === "number") return parent.psiData.cpu.some_avg10
                    return 0
                  }
                  readonly property color chipColor: Model.psiColor(cpuVal, tokens)

                  Column {
                    anchors.centerIn: parent
                    spacing: 1
                    Text {
                      text: I18n.t("CPU PSI")
                      color: "#60758C"
                      font.pixelSize: 9
                      font.bold: true
                      anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                      text: Model.formatPercent(parent.parent.cpuVal)
                      color: parent.parent.chipColor
                      font.family: "JetBrainsMono Nerd Font, monospace"
                      font.pixelSize: 11
                      font.bold: true
                      anchors.horizontalCenter: parent.horizontalCenter
                    }
                  }
                }

                // Memory Pressure Chip
                Rectangle {
                  width: (parent.width - Style.space(12)) / 3
                  height: Style.space(34)
                  radius: Style.space(6)
                  color: Qt.rgba(255, 255, 255, 0.04)
                  border.color: Qt.rgba(255, 255, 255, 0.08)

                  readonly property real memVal: {
                    if (!parent.psiData || !parent.psiData.memory) return 0
                    if (parent.psiData.memory.some && typeof parent.psiData.memory.some.avg10 === "number") return parent.psiData.memory.some.avg10
                    if (typeof parent.psiData.memory.some_avg10 === "number") return parent.psiData.memory.some_avg10
                    return 0
                  }
                  readonly property color chipColor: Model.psiColor(memVal, tokens)

                  Column {
                    anchors.centerIn: parent
                    spacing: 1
                    Text {
                      text: I18n.t("RAM PSI")
                      color: "#60758C"
                      font.pixelSize: 9
                      font.bold: true
                      anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                      text: Model.formatPercent(parent.parent.memVal)
                      color: parent.parent.chipColor
                      font.family: "JetBrainsMono Nerd Font, monospace"
                      font.pixelSize: 11
                      font.bold: true
                      anchors.horizontalCenter: parent.horizontalCenter
                    }
                  }
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(255, 255, 255, 0.08)
          }

          // -------------------------------------------------------------
          // Bloco 3: Ações Automáticas Recentes (Self-Healing Log)
          // -------------------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: I18n.t("RECENT AUTOMATIC ACTIONS")
              color: "#60758C"
              font.family: tokens.fontFamily
              font.pixelSize: 11
              font.bold: true
              font.letterSpacing: 0.5
            }

            readonly property var actions: (root.doctorState && Array.isArray(root.doctorState.recent_actions))
              ? root.doctorState.recent_actions : []

            // Empty state if no auto-actions were executed recently
            Rectangle {
              visible: parent.actions.length === 0
              width: parent.width
              height: Style.space(42)
              radius: Style.space(6)
              color: Qt.rgba(255, 255, 255, 0.03)
              border.color: Qt.rgba(255, 255, 255, 0.06)

              Text {
                anchors.centerIn: parent
                width: parent.width - Style.space(20)
                text: I18n.t("No auto-cleanup needed. Resources within parameters.")
                color: "#60758C"
                font.family: tokens.fontFamily
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
              }
            }

            // List of up to 3 recent actions
            Repeater {
              model: parent.actions.slice(0, 3)

              Rectangle {
                required property var modelData
                width: scrollColumn.width
                height: Style.space(36)
                radius: Style.space(6)
                color: Qt.rgba(255, 255, 255, 0.04)

                Row {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(8)

                  OrbitalUi.OrbitalIcon {
                    size: 16
                    name: Model.recentActionIcon(modelData.action_type || modelData.action_id)
                    tint: tokens.accent
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: modelData.description || modelData.message || I18n.t("Automatic maintenance")
                    color: "#F4F8FF"
                    font.family: tokens.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    width: parent.width - 150
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: "+" + (modelData.freed_human || Model.formatBytes(modelData.freed_bytes))
                    color: "#7BC29A"
                    font.family: "JetBrainsMono Nerd Font, monospace"
                    font.pixelSize: 11
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: "• " + Model.relativeTime(modelData.timestamp, root.panelNow)
                    color: "#60758C"
                    font.family: tokens.fontFamily
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(255, 255, 255, 0.08)
          }

          // -------------------------------------------------------------
          // Bloco 4: Integridade & Hardware (Systemd + SMART)
          // -------------------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(6)

            Text {
              text: I18n.t("INTEGRITY & HARDWARE")
              color: "#60758C"
              font.family: tokens.fontFamily
              font.pixelSize: 11
              font.bold: true
              font.letterSpacing: 0.5
            }

            // Systemd Status Card (Clickable: Inspects / Resets Failed Units)
            readonly property var sysSummary: Model.systemdStatusSummary(root.doctorState ? root.doctorState.failed_units : [])

            Rectangle {
              id: sysStatusBox
              width: parent.width
              height: Style.space(32)
              radius: Style.space(6)
              color: mouseSys.containsMouse
                ? (parent.sysSummary.ok ? Qt.rgba(123, 194, 154, 0.16) : Qt.rgba(232, 106, 106, 0.24))
                : (parent.sysSummary.ok ? Qt.rgba(123, 194, 154, 0.08) : Qt.rgba(232, 106, 106, 0.14))
              border.color: mouseSys.containsMouse
                ? (parent.sysSummary.ok ? "#7BC29A" : "#FF8A8A")
                : (parent.sysSummary.ok ? Qt.rgba(123, 194, 154, 0.25) : Qt.rgba(232, 106, 106, 0.45))

              MouseArea {
                id: mouseSys
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runTerminalCommand("/mnt/dados/projects/omarchy-orbital-theme/scripts/systemd-inspector.sh")
              }

              Row {
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(8)

                OrbitalUi.OrbitalIcon {
                  size: 16
                  name: parent.parent.parent.sysSummary.ok ? "emblem-default-symbolic" : "dialog-warning-symbolic"
                  tint: parent.parent.parent.sysSummary.ok ? "#7BC29A" : "#FF8A8A"
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: parent.parent.parent.sysSummary.text + (parent.parent.parent.sysSummary.ok ? "" : " • " + I18n.t("Click to inspect/resolve"))
                  color: parent.parent.parent.sysSummary.ok ? "#7BC29A" : "#FF8A8A"
                  font.family: tokens.fontFamily
                  font.pixelSize: 11
                  font.bold: !parent.parent.parent.sysSummary.ok
                  elide: Text.ElideRight
                  width: parent.width - 32
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            // SMART Storage Card
            readonly property var smartSummary: Model.smartStatusSummary(root.doctorState ? root.doctorState.smart : null)

            Rectangle {
              width: parent.width
              height: Style.space(32)
              radius: Style.space(6)
              color: parent.smartSummary.ok ? Qt.rgba(255, 255, 255, 0.04) : Qt.rgba(232, 106, 106, 0.14)
              border.color: parent.smartSummary.ok ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(232, 106, 106, 0.45)

              Row {
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(8)

                OrbitalUi.OrbitalIcon {
                  size: 16
                  name: parent.parent.parent.smartSummary.available ? "drive-harddisk-symbolic" : "system-lock-screen-symbolic"
                  tint: parent.parent.parent.smartSummary.ok ? (parent.parent.parent.smartSummary.available ? "#7BC29A" : "#91A4BB") : "#FF8A8A"
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: parent.parent.parent.smartSummary.text
                  color: parent.parent.parent.smartSummary.ok ? (parent.parent.parent.smartSummary.available ? "#7BC29A" : "#91A4BB") : "#FF8A8A"
                  font.family: tokens.fontFamily
                  font.pixelSize: 11
                  font.bold: !parent.parent.parent.smartSummary.ok
                  elide: Text.ElideRight
                  width: parent.width - 32
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(255, 255, 255, 0.08)
          }

          // -------------------------------------------------------------
          // Bloco 5: Footer & Ações Efetivas da Estação (Sob-Demanda)
          // -------------------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(8)

            // Button 0: Limpar Agora (Destaque — Saneamento Seguro em Segundo Plano)
            Rectangle {
              id: btnCleanNow
              width: parent.width
              height: Style.space(36)
              radius: Style.space(8)
              color: root.isSanitizing ? Qt.rgba(57, 169, 255, 0.20) : (mouseCleanNow.containsMouse ? "#4DB3FF" : "#39A9FF")
              border.color: btnCleanNow.activeFocus ? "#FFFFFF" : Qt.rgba(255, 255, 255, 0.40)
              border.width: btnCleanNow.activeFocus ? 2 : 1
              activeFocusOnTab: true

              Keys.onReturnPressed: root.startBackgroundSanitization()
              Keys.onEnterPressed: root.startBackgroundSanitization()
              Keys.onSpacePressed: root.startBackgroundSanitization()

              MouseArea {
                id: mouseCleanNow
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.isSanitizing ? Qt.WaitCursor : Qt.PointingHandCursor
                onClicked: root.startBackgroundSanitization()
              }

              Row {
                anchors.centerIn: parent
                spacing: Style.space(8)

                OrbitalUi.OrbitalIcon {
                  size: 16
                  name: root.isSanitizing ? "process-working-symbolic" : "emblem-default-symbolic"
                  tint: "#FFFFFF"
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: root.isSanitizing ? I18n.t("Cleaning Station in Background...") : I18n.t("Clean Now (Full Sanitization)")
                  color: "#FFFFFF"
                  font.family: tokens.fontFamily
                  font.pixelSize: 12
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            // Secondary Buttons Row: Abrir Relatório & Simular Limpeza
            Row {
              width: parent.width
              spacing: Style.space(10)

              // Button 1: Abrir Relatório (Scan Full in Terminal)
              Rectangle {
                id: btnReport
                width: (parent.width - Style.space(10)) / 2
                height: Style.space(34)
                radius: Style.space(8)
                color: mouseReport.containsMouse ? Qt.rgba(255, 255, 255, 0.10) : Qt.rgba(255, 255, 255, 0.06)
                border.color: btnReport.activeFocus ? "#39A9FF" : (mouseReport.containsMouse ? Qt.rgba(255, 255, 255, 0.28) : Qt.rgba(255, 255, 255, 0.16))
                border.width: btnReport.activeFocus ? 2 : 1
                activeFocusOnTab: true

                Keys.onReturnPressed: root.runTerminalCommand("omarchy-doctor scan --full")
                Keys.onEnterPressed: root.runTerminalCommand("omarchy-doctor scan --full")
                Keys.onSpacePressed: root.runTerminalCommand("omarchy-doctor scan --full")

                MouseArea {
                  id: mouseReport
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.runTerminalCommand("omarchy-doctor scan --full")
                }

                Row {
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  OrbitalUi.OrbitalIcon {
                    size: 16
                    name: "text-x-generic-symbolic"
                    tint: "#F4F8FF"
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: I18n.t("Open Report")
                    color: "#F4F8FF"
                    font.family: tokens.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }

              // Button 2: Simular Limpeza (Dry-Run in Terminal)
              Rectangle {
                id: btnDryRun
                width: (parent.width - Style.space(10)) / 2
                height: Style.space(34)
                radius: Style.space(8)
                color: mouseDryRun.containsMouse ? Qt.rgba(57, 169, 255, 0.26) : Qt.rgba(57, 169, 255, 0.16)
                border.color: btnDryRun.activeFocus ? "#FFFFFF" : (mouseDryRun.containsMouse ? "#5BC0FF" : Qt.rgba(57, 169, 255, 0.55))
                border.width: btnDryRun.activeFocus ? 2 : 1
                activeFocusOnTab: true

                Keys.onReturnPressed: root.runTerminalCommand("omarchy-doctor fix --dry-run")
                Keys.onEnterPressed: root.runTerminalCommand("omarchy-doctor fix --dry-run")
                Keys.onSpacePressed: root.runTerminalCommand("omarchy-doctor fix --dry-run")

                MouseArea {
                  id: mouseDryRun
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.runTerminalCommand("omarchy-doctor fix --dry-run")
                }

                Row {
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  OrbitalUi.OrbitalIcon {
                    size: 16
                    name: "system-run-symbolic"
                    tint: "#FFFFFF"
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: I18n.t("Simulate Cleanup")
                    color: "#FFFFFF"
                    font.family: tokens.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
