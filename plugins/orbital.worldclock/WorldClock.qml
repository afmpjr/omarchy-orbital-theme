// Orbital World Clock — the mockup's clock panel: world clock, alarms,
// timer, and a Pomodoro-style focus mode, as four tabs in one popup.
//
// Real data only, same discipline as the rest of this project:
//   - World clock: real IANA timezones via `TZ=<zone> date`, refreshed on
//     a real Timer — not a hand-rolled offset table (DST, half-hour
//     zones, etc. are all real edge cases a raw UTC-offset calculation
//     gets wrong). The local city (Dublin) isn't a mockup coincidence —
//     confirmed via `timedatectl show --property=Timezone --value`
//     before writing this file: this machine's real system timezone
//     genuinely is Europe/Dublin. GMT offsets are computed from the
//     same `date +%z` output, not hardcoded either.
//   - Alarms: this system has no real alarm/scheduling daemon exposed to
//     the shell — `omarchy reminder` (confirmed real via `omarchy
//     commands`) is the one real "notify me later" mechanism that
//     exists, so alarms here ARE reminders, read/written through it
//     (`omarchy reminder show -j` / `omarchy reminder <minutes>
//     [message]`), not a separate fabricated alarm store.
//   - Timer / Focus: a real QML Timer counting down, no backend needed.
//     Focus's Pomodoro/Short Break/Long Break are just different preset
//     durations feeding the same countdown.
//
// Visual structure follows the mockup closely (checked directly against
// it, not just "structurally similar"): big local time + date header
// with a settings glyph, icon+underline tabs (not filled pills), a
// globe icon + GMT offset + overflow-menu glyph per city row, an
// "+ Add city" affordance, and a Focus quick-widget shown inline under
// the city list on the Clock tab (in addition to its own full Focus
// tab) — all present in the reference image, not guessed.
//
// Same safe overlay shape as orbital.account/orbital.launcher — static
// WlrKeyboardFocus.Exclusive, visible: opened, no runtime enum toggling
// (see orbital.dock's Dock.qml header for why that distinction matters).

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string activeTab: "clock"
  readonly property var tabOrder: ["clock", "alarms", "timer", "focus"]

  function cycleTab(delta) {
    var idx = root.tabOrder.indexOf(root.activeTab)
    if (idx < 0) idx = 0
    idx = (idx + delta + root.tabOrder.length) % root.tabOrder.length
    root.activeTab = root.tabOrder[idx]
  }

  // Card look (colour/alpha/border) comes from the theme's [menu] tokens
  // via Color.menu / Border.surfaceSpec — see the Orbital theme shell.toml.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(1)))
  property color scrim: Color.menu.scrim
  // Radius follows Style.cornerRadius (mirrors Hyprland decoration:rounding).
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.family
  property int panelWidth: Style.space(360)
  property int panelHeight: Style.space(620)

  function open(payloadJson) {
    root.opened = true
    root.refreshClocks()
    root.refreshAlarms()
  }

  function close() {
    root.opened = false
  }

  function toggle(payloadJson) {
    if (root.opened) root.close()
    else root.open(payloadJson)
  }

  // ------------------------------------------------------------- clock

  property var cities: [
    { name: "Dublin", tz: "Europe/Dublin", local: true },
    { name: "London", tz: "Europe/London", local: false },
    { name: "São Paulo", tz: "America/Sao_Paulo", local: false },
    { name: "Cuiabá", tz: "America/Cuiaba", local: false }
  ]

  // Real add-city picker: the full system IANA timezone list (real
  // data — `timedatectl list-timezones`, ~600 real zones — not a
  // hand-picked handful that always adds the same first unused entry
  // in a fixed order, which is what this used to do before the user
  // pointed out "Add city" kept adding New York every time). Fetched
  // once, filtered live as the user types.
  property var allTimezones: []
  property bool addingCity: false
  property string cityQuery: ""

  Process {
    id: timezoneListProc
    command: ["timedatectl", "list-timezones"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.allTimezones = text.split("\n").filter(function(line) { return line.length > 0 })
      }
    }
    Component.onCompleted: running = true
  }

  function cityDisplayName(tz) {
    var segments = String(tz || "").split("/")
    var last = segments[segments.length - 1] || tz
    return last.replace(/_/g, " ")
  }

  function existingTzSet() {
    var existing = {}
    for (var i = 0; i < root.cities.length; i++) existing[root.cities[i].tz] = true
    return existing
  }

  readonly property var citySearchResults: {
    var q = root.cityQuery.trim().toLowerCase()
    if (q.length === 0) return []
    var existing = root.existingTzSet()
    var out = []
    for (var i = 0; i < root.allTimezones.length && out.length < 8; i++) {
      var tz = root.allTimezones[i]
      if (existing[tz]) continue
      var haystack = tz.toLowerCase().replace(/_/g, " ")
      if (haystack.indexOf(q) === -1) continue
      out.push({ tz: tz, name: root.cityDisplayName(tz) })
    }
    return out
  }

  function startAddingCity() {
    root.addingCity = true
    root.cityQuery = ""
    Qt.callLater(function() { if (citySearchInput) citySearchInput.forceActiveFocus() })
  }

  function cancelAddingCity() {
    root.addingCity = false
    root.cityQuery = ""
  }

  function addCityByTz(tz, name) {
    root.cities = root.cities.concat([{ name: name, tz: tz, local: false }])
    root.refreshClocks()
    root.cancelAddingCity()
  }
  property var cityTimes: ({})
  readonly property string localTime: root.cityTimes["Europe/Dublin"] ? root.cityTimes["Europe/Dublin"].split("|")[0] : "--:--"
  readonly property string localDate: {
    var info = root.cityTimes["Europe/Dublin"]
    return info ? info.split("|")[3] : ""
  }

  function refreshClocks() {
    clockProc.running = false
    clockProc.running = true
  }

  // Per city: HH:MM | short weekday, month day | GMT offset (from the
  // real %z, e.g. "+0100" -> "GMT+1") | full weekday, month day, year
  // (for the header, computed off the local/Dublin entry only).
  Process {
    id: clockProc
    command: {
      var parts = []
      for (var i = 0; i < root.cities.length; i++) {
        var c = root.cities[i]
        parts.push('echo "' + c.tz + '=$(TZ=' + c.tz + ' date "+%H:%M|%a, %b %-d|%z|%A, %B %-d, %Y")"')
      }
      return ["bash", "-c", parts.join('; ')]
    }
    stdout: SplitParser {
      onRead: function(line) {
        var eq = line.indexOf("=")
        if (eq < 0) return
        var tz = line.slice(0, eq)
        var value = line.slice(eq + 1)
        var next = {}
        for (var k in root.cityTimes) next[k] = root.cityTimes[k]
        next[tz] = value
        root.cityTimes = next
      }
    }
  }

  function gmtLabelFor(tz) {
    var info = root.cityTimes[tz]
    if (!info) return ""
    var raw = info.split("|")[2] || ""
    if (raw.length < 5) return ""
    var sign = raw.charAt(0)
    var hours = parseInt(raw.slice(1, 3), 10)
    var minutes = raw.slice(3, 5)
    var text = "GMT" + sign + hours
    if (minutes !== "00") text += ":" + minutes
    return text
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.refreshClocks()
  }

  // ------------------------------------------------------------ alarms

  property var alarms: []
  property string newAlarmMinutes: ""
  property string newAlarmMessage: ""

  function refreshAlarms() {
    alarmsProc.running = false
    alarmsProc.running = true
  }

  Process {
    id: alarmsProc
    command: ["omarchy", "reminder", "show", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          root.alarms = (data && data.reminders) || []
        } catch (e) {
          root.alarms = []
        }
      }
    }
  }

  function addAlarm() {
    var minutes = parseInt(root.newAlarmMinutes, 10)
    if (!minutes || minutes <= 0) return
    var args = ["omarchy", "reminder", String(minutes)]
    if (root.newAlarmMessage.length > 0) args.push(root.newAlarmMessage)
    Quickshell.execDetached(args)
    root.newAlarmMinutes = ""
    root.newAlarmMessage = ""
    // execDetached returns before `omarchy reminder` has registered its
    // timer, so an immediate refresh reads the old (empty) list — found
    // live with a real click test.
    alarmRefreshTimer.restart()
  }

  Timer {
    id: alarmRefreshTimer
    interval: 700
    onTriggered: root.refreshAlarms()
  }

  // -------------------------------------------------------- timer/focus

  property int countdownTotal: 0
  property int countdownRemaining: 0
  property bool countdownRunning: false

  readonly property var focusPresets: ({
    pomodoro: 25 * 60,
    short: 5 * 60,
    long: 15 * 60
  })

  readonly property var focusQuotes: [
    "A focused mind builds extraordinary things.",
    "Small steps, done consistently, add up.",
    "One task at a time.",
    "Deep work beats busy work."
  ]
  readonly property string focusQuote: focusQuotes[new Date().getDate() % focusQuotes.length]

  function startCountdown(seconds) {
    root.countdownTotal = seconds
    root.countdownRemaining = seconds
    root.countdownRunning = true
  }

  function toggleCountdown() {
    if (root.countdownTotal <= 0) root.startCountdown(root.focusPresets.pomodoro)
    else if (root.countdownRemaining > 0) root.countdownRunning = !root.countdownRunning
  }

  function resetCountdown() {
    root.countdownRunning = false
    root.countdownRemaining = 0
    root.countdownTotal = 0
  }

  function formatCountdown(seconds) {
    var m = Math.floor(seconds / 60)
    var s = seconds % 60
    return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
  }

  Timer {
    interval: 1000
    running: root.countdownRunning && root.opened
    repeat: true
    onTriggered: {
      if (root.countdownRemaining <= 1) {
        root.countdownRemaining = 0
        root.countdownRunning = false
      } else {
        root.countdownRemaining -= 1
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "orbital-worldclock"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Item {
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        // The city search field needs its own arrow keys (cursor
        // movement) and Tab/typing untouched — only Escape is special
        // here (closes the picker, not the whole panel), everything
        // else falls through to whatever has focus.
        if (root.addingCity) {
          if (event.key === Qt.Key_Escape) { root.cancelAddingCity(); event.accepted = true }
          return
        }
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right) {
          root.cycleTab(1); event.accepted = true
        } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left) {
          root.cycleTab(-1); event.accepted = true
        }
      }
    }

    BorderSurface {
      id: card
      width: root.panelWidth
      height: root.panelHeight
      radius: root.cornerRadius
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: Style.space(12)
      anchors.bottomMargin: Style.space(44)
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.space(12)

        // ---- Header: big local time, full local date. The mockup shows
        // a settings glyph here too, but there's no real destination for
        // it (no timezone/clock settings panel exists in Omarchy) — left
        // out rather than shipping a gear that looks actionable and does
        // nothing, same call as every other "no real backing" item this
        // project has dropped (see orbital.account's own header comment).
        Text {
          id: headerTime
          text: root.localTime
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title * 2.6
          font.weight: Font.DemiBold
        }

        Text {
          width: parent.width
          text: root.localDate
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.6
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Item { width: 1; height: Style.space(2) }

        // ---- Tab strip: icon + label, underline on the active tab.
        Row {
          width: parent.width
          spacing: Style.space(4)

          // Item, not Column, at the root: Column forbids `anchors.fill`
          // on direct children too (not just centerIn/verticalCenter —
          // found the hard way, the click MouseArea below silently broke
          // tab switching until this was an Item wrapping an inner
          // Column instead). The inner Column only stacks the label and
          // underline; the click target is a plain sibling that can
          // anchor.fill this outer Item freely.
          component TabButton: Item {
            id: tabButton
            required property string tabId
            required property string label
            required property string iconName
            readonly property bool active: root.activeTab === tabId
            width: (parent.width - Style.space(4) * 3) / 4
            implicitHeight: tabColumn.implicitHeight

            Column {
              id: tabColumn
              width: parent.width
              spacing: Style.space(4)

              Row {
                x: (tabColumn.width - width) / 2
                spacing: Style.space(5)

                Image {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(18)
                  height: Style.space(18)
                  fillMode: Image.PreserveAspectFit
                  opacity: tabButton.active ? 1 : 0.55
                  source: Quickshell.iconPath(tabButton.iconName, true)
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: tabButton.label
                  textFormat: Text.PlainText
                  color: tabButton.active ? Color.accent : root.foreground
                  opacity: tabButton.active ? 1 : 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Rectangle {
                x: (tabColumn.width - width) / 2
                width: parent.width * 0.85
                height: Style.space(3)
                radius: height / 2
                color: Color.accent
                visible: tabButton.active
              }
              Item { width: 1; height: Style.space(3); visible: !tabButton.active }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.activeTab = tabButton.tabId
            }
          }

          TabButton { tabId: "clock"; label: "Clock"; iconName: "clock-symbolic" }
          TabButton { tabId: "alarms"; label: "Alarms"; iconName: "alarm-symbolic" }
          TabButton { tabId: "timer"; label: "Timer"; iconName: "timer-alt-symbolic" }
          TabButton { tabId: "focus"; label: "Focus"; iconName: "focus-windows-symbolic" }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: root.foreground
          opacity: 0.12
        }

        // ---- Clock tab: city rows + add-city affordance + inline Focus.
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.activeTab === "clock"

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: !root.addingCity

          Repeater {
            model: root.cities
            delegate: Row {
              id: cityRow
              required property var modelData
              required property int index
              readonly property string timeInfo: root.cityTimes[modelData.tz] || ""
              readonly property string timePart: timeInfo.split("|")[0] || "--:--"
              readonly property string datePart: timeInfo.split("|")[1] || ""

              width: parent.width
              height: Style.space(36)
              spacing: Style.space(10)

              Image {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(20)
                height: Style.space(20)
                fillMode: Image.PreserveAspectFit
                opacity: 0.7
                source: Quickshell.iconPath("globe-symbolic", true)
              }

              Column {
                width: parent.width - Style.space(130)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                  text: cityRow.modelData.name
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  text: cityRow.datePart
                  textFormat: Text.PlainText
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall - 1
                }
              }

              Column {
                width: Style.space(70)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignRight
                  text: cityRow.timePart
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Row {
                  anchors.right: parent.right
                  spacing: Style.space(4)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: cityRow.modelData.local
                    width: Style.space(5)
                    height: Style.space(5)
                    radius: width / 2
                    color: Color.accent
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: cityRow.modelData.local ? "Local" : root.gmtLabelFor(cityRow.modelData.tz)
                    textFormat: Text.PlainText
                    color: cityRow.modelData.local ? Color.accent : root.foreground
                    opacity: cityRow.modelData.local ? 1 : 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall - 1
                  }
                }
              }

              Image {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(16)
                height: Style.space(16)
                fillMode: Image.PreserveAspectFit
                opacity: 0.5
                source: Quickshell.iconPath("view-more-symbolic", true)

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (cityRow.modelData.local) return
                    var next = root.cities.slice()
                    next.splice(cityRow.index, 1)
                    root.cities = next
                  }
                }
              }
            }
          }

          Rectangle {
            id: addCityButton
            width: parent.width
            height: Style.space(36)
            radius: height / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)

            Row {
              anchors.centerIn: parent
              spacing: Style.space(6)
              Image {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(14)
                height: Style.space(14)
                fillMode: Image.PreserveAspectFit
                opacity: 0.7
                source: Quickshell.iconPath("list-add-symbolic", true)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Add city"
                textFormat: Text.PlainText
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.startAddingCity()
            }
          }
          }

          // ---- Add-city search picker: real IANA zones filtered live,
          // shown in place of the city list + button above while active.
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.addingCity

            Row {
              width: parent.width
              spacing: Style.space(8)

              Rectangle {
                width: parent.width - Style.space(32) - Style.space(8)
                height: Style.space(32)
                radius: Style.space(8)
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                border.width: citySearchInput.activeFocus ? 1 : 0
                border.color: Color.accent

                TextInput {
                  id: citySearchInput
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  text: root.cityQuery
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  verticalAlignment: TextInput.AlignVCenter
                  onTextChanged: root.cityQuery = text
                  Keys.onEscapePressed: root.cancelAddingCity()

                  Text {
                    anchors.fill: parent
                    visible: citySearchInput.text.length === 0
                    text: "Search cities…"
                    textFormat: Text.PlainText
                    color: root.foreground
                    opacity: 0.4
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    verticalAlignment: Text.AlignVCenter
                  }
                }
              }

              Rectangle {
                width: Style.space(32)
                height: Style.space(32)
                radius: Style.space(8)
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                Image {
                  anchors.centerIn: parent
                  width: Style.space(14)
                  height: Style.space(14)
                  fillMode: Image.PreserveAspectFit
                  opacity: 0.7
                  source: Quickshell.iconPath("window-close-symbolic", true)
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.cancelAddingCity()
                }
              }
            }

            Text {
              width: parent.width
              visible: root.cityQuery.trim().length > 0 && root.citySearchResults.length === 0
              text: "No matches"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.citySearchResults
              delegate: Rectangle {
                id: resultRow
                required property var modelData
                width: parent ? parent.width : 0
                height: Style.space(32)
                radius: Style.space(8)
                color: resultMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"

                Row {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    width: parent.width * 0.55
                    text: resultRow.modelData.name
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    width: parent.width * 0.45 - Style.space(8)
                    horizontalAlignment: Text.AlignRight
                    text: resultRow.modelData.tz
                    textFormat: Text.PlainText
                    elide: Text.ElideLeft
                    opacity: 0.45
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall - 1
                  }
                }

                MouseArea {
                  id: resultMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.addCityByTz(resultRow.modelData.tz, resultRow.modelData.name)
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: root.foreground
            opacity: 0.12
          }

          Text {
            text: "Focus"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          FocusWidget { compact: true }
        }

        // ---- Alarms tab
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.activeTab === "alarms"

          Text {
            visible: root.alarms.length === 0
            text: "No reminders set"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.alarms
            delegate: Row {
              required property var modelData
              width: parent ? parent.width : 0
              height: Style.space(28)
              spacing: Style.space(8)

              Image {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(16)
                height: Style.space(16)
                fillMode: Image.PreserveAspectFit
                opacity: 0.7
                source: Quickshell.iconPath("alarm-symbolic", true)
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Style.space(24)
                text: String((modelData && modelData.label) || (modelData && modelData.message) || "")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          // New-reminder form: a labeled section (not two mystery boxes),
          // real placeholders so an empty field still explains itself,
          // Enter-to-submit from either field, and a button that's
          // visibly inert until the one required field (minutes) is
          // actually valid — instead of always looking clickable.
          Column {
            width: parent.width
            spacing: Style.space(6)
            topPadding: Style.space(8)

            Text {
              text: "New reminder"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall - 1
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Rectangle {
                width: Style.space(64)
                height: Style.space(32)
                radius: Style.space(8)
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                border.width: minutesInput.activeFocus ? 1 : 0
                border.color: Color.accent

                TextInput {
                  id: minutesInput
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  text: root.newAlarmMinutes
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  validator: IntValidator { bottom: 1; top: 1440 }
                  verticalAlignment: TextInput.AlignVCenter
                  onTextChanged: root.newAlarmMinutes = text
                  onAccepted: root.addAlarm()

                  Text {
                    anchors.fill: parent
                    visible: minutesInput.text.length === 0
                    text: "Min"
                    textFormat: Text.PlainText
                    color: root.foreground
                    opacity: 0.4
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    verticalAlignment: Text.AlignVCenter
                  }
                }
              }

              Rectangle {
                width: parent.width - Style.space(64) - Style.space(36) - Style.space(12)
                height: Style.space(32)
                radius: Style.space(8)
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                border.width: messageInput.activeFocus ? 1 : 0
                border.color: Color.accent

                TextInput {
                  id: messageInput
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  text: root.newAlarmMessage
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  verticalAlignment: TextInput.AlignVCenter
                  onTextChanged: root.newAlarmMessage = text
                  onAccepted: root.addAlarm()

                  Text {
                    anchors.fill: parent
                    visible: messageInput.text.length === 0
                    text: "What for? (optional)"
                    textFormat: Text.PlainText
                    color: root.foreground
                    opacity: 0.4
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    verticalAlignment: Text.AlignVCenter
                  }
                }
              }

              Rectangle {
                readonly property bool canSubmit: parseInt(root.newAlarmMinutes, 10) > 0
                width: Style.space(36)
                height: Style.space(32)
                radius: Style.space(8)
                color: Color.accent
                opacity: canSubmit ? 1 : 0.35

                Image {
                  anchors.centerIn: parent
                  width: Style.space(16)
                  height: Style.space(16)
                  fillMode: Image.PreserveAspectFit
                  source: Quickshell.iconPath("list-add-symbolic", true)
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: parent.canSubmit
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.addAlarm()
                }
              }
            }
          }
        }

        // ---- Timer tab
        component CountdownUi: Column {
          id: countdownUi
          required property var presets
          width: parent ? parent.width : 0
          spacing: Style.space(10)

          Text {
            // Column forbids anchors on direct children — x binding
            // instead (see TabButton above for the same fix, first found
            // there).
            x: (countdownUi.width - width) / 2
            text: root.formatCountdown(root.countdownRemaining)
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title * 1.6
          }

          Row {
            x: (countdownUi.width - width) / 2
            spacing: Style.space(8)

            Repeater {
              model: countdownUi.presets
              delegate: Rectangle {
                id: timerPreset
                required property var modelData
                readonly property bool active: root.countdownTotal === modelData.seconds
                width: presetLabel.implicitWidth + Style.space(16)
                height: Style.space(28)
                radius: height / 2
                color: active ? Color.accent : "transparent"
                border.width: active ? 0 : 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

                Text {
                  id: presetLabel
                  anchors.centerIn: parent
                  text: timerPreset.modelData.label
                  textFormat: Text.PlainText
                  color: timerPreset.active ? Color.background : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.startCountdown(timerPreset.modelData.seconds)
                }
              }
            }
          }

          Row {
            x: (countdownUi.width - width) / 2
            spacing: Style.space(10)

            Rectangle {
              width: Style.space(72)
              height: Style.space(32)
              radius: height / 2
              color: Color.accent
              visible: root.countdownTotal > 0
              Text {
                anchors.centerIn: parent
                text: root.countdownRunning ? "Pause" : "Start"
                textFormat: Text.PlainText
                color: Color.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleCountdown() }
            }

            Rectangle {
              width: Style.space(72)
              height: Style.space(32)
              radius: height / 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
              visible: root.countdownTotal > 0
              Text {
                anchors.centerIn: parent
                text: "Reset"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.resetCountdown() }
            }
          }
        }

        CountdownUi {
          visible: root.activeTab === "timer"
          presets: [
            { label: "5 min", seconds: 5 * 60 },
            { label: "10 min", seconds: 10 * 60 },
            { label: "20 min", seconds: 20 * 60 },
            { label: "30 min", seconds: 30 * 60 }
          ]
        }

        // ---- Focus tab (full-size version of the inline widget above)
        FocusWidget {
          visible: root.activeTab === "focus"
          compact: false
        }
      }
    }

  }

  // Shared between the Clock tab's inline preview and the Focus tab's
  // full view — same Pomodoro/Short Break/Long Break + countdown +
  // play/reset, just a smaller vertical footprint when compact. A direct
  // child of root (not nested inside PanelWindow above) — QML6 `component`
  // declarations must sit at the same nesting level as the type's other
  // direct children, confirmed earlier this session against first-party
  // Bar.qml's own `component ModuleList: Loader {...}` placement.
  component FocusWidget: Column {
    id: focusWidget
    property bool compact: false
    width: parent ? parent.width : 0
    spacing: Style.space(8)

    Row {
      x: (focusWidget.width - width) / 2
      spacing: Style.space(6)

      Repeater {
        model: [
          { label: "Pomodoro", seconds: root.focusPresets.pomodoro },
          { label: "Short Break", seconds: root.focusPresets.short },
          { label: "Long Break", seconds: root.focusPresets.long }
        ]
        delegate: Rectangle {
          id: focusPreset
          required property var modelData
          readonly property bool active: root.countdownTotal === modelData.seconds
          width: focusPresetLabel.implicitWidth + Style.space(16)
          height: Style.space(26)
          radius: height / 2
          color: active ? Color.accent : "transparent"
          border.width: active ? 0 : 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

          Text {
            id: focusPresetLabel
            anchors.centerIn: parent
            text: focusPreset.modelData.label
            textFormat: Text.PlainText
            color: focusPreset.active ? Color.background : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall - 1
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.startCountdown(focusPreset.modelData.seconds)
          }
        }
      }
    }

    Row {
      x: (focusWidget.width - width) / 2
      spacing: Style.space(10)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.formatCountdown(root.countdownTotal > 0 ? root.countdownRemaining : root.focusPresets.pomodoro)
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: focusWidget.compact ? Style.font.title * 1.2 : Style.font.title * 1.8
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(38)
        height: Style.space(38)
        radius: width / 2
        color: Color.accent

        Image {
          anchors.centerIn: parent
          width: Style.space(16)
          height: Style.space(16)
          fillMode: Image.PreserveAspectFit
          source: Quickshell.iconPath(root.countdownRunning ? "media-playback-pause-symbolic" : "media-playback-start-symbolic", true)
        }

        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleCountdown() }
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "“" + root.focusQuote + "”"
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.italic: true
      font.pixelSize: Style.font.bodySmall
    }
  }
}
