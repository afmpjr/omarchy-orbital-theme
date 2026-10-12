import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "NotificationsModel.js" as Model
import "../orbital.ui" as OrbitalUi

// The notification center popup: the archive newest-first, with the sender,
// the subject, the message and a relative age per row. The bell widget owns
// every byte of state; this panel only reads it off its host widget and asks
// it to dismiss or clear. It never touches a service object.
Panel {
  id: root
  function tr(s) { return OrbitalUi.OrbitalI18n.t(s) }
  moduleName: "orbital.notifications"
  ipcTarget: "orbital.notifications"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget (same convention orbital.clock follows).
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int configuredWidth: hostWidget ? hostWidget.panelWidth : 420
  // The list virtualizes, but the card still sizes itself up front: cap the
  // visible rows so a 1000-entry archive opens a screen-fitting card, not a
  // screen-filling one.
  readonly property var visibleEntries: hostWidget ? hostWidget.entries.slice(0, 300) : []
  readonly property bool dndOn: hostWidget ? hostWidget.dnd === true : false
  readonly property bool dndWritable: hostWidget ? hostWidget.dndWritable === true : false
  readonly property real rowHeight: Style.space(78)

  // Re-renders relative ages without reopening the panel.
  property int nowTick: 0

  // One literal tr() per unit: the i18n gate matches static strings only, so a
  // dynamic tr(parts.unit) would read as an unused dictionary entry.
  function unitLabel(unit) {
    if (unit === "minute") return tr("minute")
    if (unit === "minutes") return tr("minutes")
    if (unit === "hour") return tr("hour")
    if (unit === "hours") return tr("hours")
    if (unit === "day") return tr("day")
    if (unit === "days") return tr("days")
    if (unit === "week") return tr("week")
    return tr("weeks")
  }

  function relativeText(timestamp) {
    // nowTick is read so relative ages re-render on every tick.
    if (root.nowTick < -1) return ""
    var parts = Model.relativeParts(timestamp, Date.now())
    if (parts.kind === "now") return tr("now")
    if (parts.kind === "date") return Qt.formatDate(new Date(Number(timestamp) || 0), Qt.locale().dateFormat(Locale.ShortFormat))
    var unit = unitLabel(parts.unit)
    // Word order stays English ("5 minutes ago"); the Portuguese dictionary
    // renders it as "5 minutos atrás", which needs no special case here.
    return parts.amount + " " + unit + " " + tr("ago")
  }

  function iconFile(entry) {
    var direct = String((entry && entry.appIcon) || "")
    if (direct.indexOf("file://") === 0) return direct
    // QML Image wants a URL: a bare absolute path would resolve relative.
    if (direct.charAt(0) === "/") return "file://" + direct
    return ""
  }

  function iconName(entry) {
    var direct = String((entry && entry.appIcon) || "")
    if (direct && direct.indexOf("file://") !== 0 && direct.charAt(0) !== "/") return direct
    var app = String((entry && entry.app) || "")
    if (app) return app
    return "notifications-bell-symbolic"
  }

  function open() {
    if (hostWidget && typeof hostWidget.markSeen === "function") hostWidget.markSeen()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowTick++
  }

  OrbitalUi.OrbitalTokens { id: tokens }

  component ActionButton: Rectangle {
    id: actionRoot
    property string label: ""
    property bool actionEnabled: true
    property color labelColor: "white"
    property string labelFontFamily: ""
    signal clicked()
    width: Math.max(Style.space(64), actionLabel.implicitWidth + Style.space(20))
    height: Style.space(28)
    radius: Style.space(8)
    color: actionMouse.containsMouse && actionEnabled ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)
    border.color: Qt.rgba(1, 1, 1, 0.18)
    border.width: 1
    opacity: actionEnabled ? 1.0 : 0.45

    Text {
      id: actionLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: actionRoot.label
      color: actionRoot.labelColor
      font.family: actionRoot.labelFontFamily
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      enabled: actionRoot.actionEnabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: actionRoot.clicked()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.configuredWidth))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight)

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        }
      }

      Column {
        id: panelColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        Item {
          width: parent.width
          height: Math.max(titleText.implicitHeight, clearButton.height)

          Text {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: tr("Notifications")
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          ActionButton {
            id: clearButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.visibleEntries.length > 0
            label: tr("Clear all")
            labelColor: root.contentForeground
            labelFontFamily: root.contentFontFamily
            onClicked: {
              if (root.hostWidget && typeof root.hostWidget.clearAll === "function") root.hostWidget.clearAll()
            }
          }
        }

        Item {
          width: parent.width
          height: dndButton.height

          ActionButton {
            id: dndButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            actionEnabled: root.dndWritable
            label: root.dndOn ? tr("Do Not Disturb: on") : tr("Do Not Disturb: off")
            labelColor: root.contentForeground
            labelFontFamily: root.contentFontFamily
            onClicked: {
              if (root.hostWidget && typeof root.hostWidget.toggleDnd === "function") root.hostWidget.toggleDnd()
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: root.contentForeground
          opacity: 0.12
        }

        Text {
          visible: root.visibleEntries.length === 0
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          topPadding: Style.space(24)
          bottomPadding: Style.space(24)
          textFormat: Text.PlainText
          text: tr("No notifications yet")
          color: root.contentForeground
          opacity: 0.6
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }

        ListView {
          id: historyList
          visible: root.visibleEntries.length > 0
          width: parent.width
          height: Math.min(Style.space(390), Math.max(root.rowHeight, root.visibleEntries.length * root.rowHeight))
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.visibleEntries
          delegate: Item {
            required property var modelData
            width: historyList.width
            height: root.rowHeight

            Rectangle {
              anchors.fill: parent
              radius: Style.space(8)
              color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(2)
              anchors.topMargin: Style.space(8)
              anchors.bottomMargin: Style.space(8)
              spacing: Style.space(10)

              Item {
                width: Style.space(36)
                height: parent.height

                OrbitalUi.OrbitalIcon {
                  anchors.centerIn: parent
                  size: 32
                  name: root.iconFile(modelData) ? "" : root.iconName(modelData)
                  source: root.iconFile(modelData)
                  preserveColors: root.iconFile(modelData) !== ""
                  tint: root.contentForeground
                }
              }

              Column {
                width: parent.width - 36 - dismissSlot.width - thumbSlot.width - parent.spacing * 3
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: (modelData.app ? modelData.app + "  ·  " : "") + root.relativeText(modelData.timestamp)
                  color: root.contentForeground
                  opacity: 0.55
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: modelData.summary
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  maximumLineCount: 1
                  text: modelData.body
                  color: root.contentForeground
                  opacity: 0.75
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Item {
                id: thumbSlot
                width: modelData.image ? Style.space(52) : 0
                visible: modelData.image !== ""
                height: parent.height

                Image {
                  anchors.fill: parent
                  source: modelData.image
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                }
              }

              Item {
                id: dismissSlot
                width: Style.space(28)
                height: parent.height

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "×"
                  color: dismissMouse.containsMouse ? root.contentForeground : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.45)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                }

                MouseArea {
                  id: dismissMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (root.hostWidget && typeof root.hostWidget.dismissEntry === "function")
                      root.hostWidget.dismissEntry(modelData.key)
                  }
                }
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.NoButton
            }
          }
        }
      }
    }
  }
}
