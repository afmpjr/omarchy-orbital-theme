import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../orbital.ui" as OrbitalUi

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel — same hero-over-detail composition, same
// spacing scale, same small-caps labels.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen —
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  function tr(s) { return OrbitalUi.OrbitalI18n.t(s) }
  moduleName: "omarchy.clock"
  ipcTarget: "omarchy.clock"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // Day and month names follow the interface language (English, or Portuguese when the system
  // locale is pt*; see orbital.ui/OrbitalI18n.qml). Where the week starts comes from the system
  // locale instead: that is a regional convention rather than a translation, and it stays
  // overridable above.
  readonly property var labelLocale: Qt.locale(OrbitalUi.OrbitalI18n.pt ? "pt_BR" : "en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)


  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // Fit the seven columns to the card's real inner width instead of a fixed
  // size: the fixed 42-unit cells made the grid (and everything sized off
  // it) wider than the visible area, clipping the weather footer's right
  // side ("L: 9°" without the C).
  readonly property int cellWidth: Math.max(Style.space(28), Math.floor((calendarScroll.width - cellSpacing * 6) / 7))
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(4)

  // ---- Weather: real data, `wttr.in`'s bare IP-based lookup — not
  // `omarchy-weather-location`/`omarchy-weather-status`, which on this
  // network resolve to a broken "53.347200" (the location script's own
  // `${name%%,*}` truncation mangling wttr.in's coordinate-only IP
  // fallback into a useless number, a pre-existing bug in those packaged,
  // read-only scripts, not something this plugin can fix). The bare `j1`
  // endpoint's own `nearest_area.region` still resolves correctly on this
  // network (confirmed: "Dublin", matching the Europe/Dublin system
  // timezone already established elsewhere in this project) — `region`
  // over `areaName` because wttr.in's `areaName` is often a small
  // neighbourhood ("Mountjoy") rather than the city name.
  property string weatherCity: ""
  property string weatherTempC: ""
  property string weatherDesc: ""
  property string weatherHighC: ""
  property string weatherLowC: ""
  property string weatherIconGlyph: ""
  property bool weatherAvailable: false

  function refreshWeather() {
    weatherDataProc.running = false
    weatherDataProc.running = true
    weatherIconProc.running = false
    weatherIconProc.running = true
  }

  function open() {
    refresh()
    root.refreshWeather()
    reminderProc.running = false
    reminderProc.running = true
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
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

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  Process {
    id: weatherDataProc
    command: ["curl", "-fsS", "--max-time", "5", "https://wttr.in/?format=j1"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          var area = data.nearest_area[0]
          var current = data.current_condition[0]
          var todayWeather = data.weather[0]
          var region = (area.region[0] && area.region[0].value) || ""
          var areaName = (area.areaName[0] && area.areaName[0].value) || ""
          root.weatherCity = region.length > 0 ? region : areaName
          root.weatherTempC = current.temp_C
          root.weatherDesc = current.weatherDesc[0].value
          root.weatherHighC = todayWeather.maxtempC
          root.weatherLowC = todayWeather.mintempC
          root.weatherAvailable = root.weatherCity.length > 0
        } catch (e) {
          root.weatherAvailable = false
        }
      }
    }
  }

  // Real, day/night-aware glyph from the packaged `omarchy weather icon`
  // command — reused rather than reimplemented so the icon always agrees
  // with whatever that command considers current conditions.
  Process {
    id: weatherIconProc
    command: ["omarchy", "weather", "icon"]
    stdout: StdioCollector {
      onStreamFinished: { root.weatherIconGlyph = text.trim() }
    }
  }

  Timer {
    interval: 20 * 60 * 1000
    running: root.opened
    repeat: true
    onTriggered: root.refreshWeather()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    // Not centerOnBar: that positions the card at screen-center-x
    // regardless of where the trigger sits, and orbital.clock lives in the
    // bar's right section (confirmed via shell.json), not its center —
    // centerOnBar was popping the calendar up in the middle of the
    // screen, disconnected from the date button that opened it. Anchored
    // positioning keeps it above the actual button, the same convention
    // orbital.worldclock's own popup already follows (bottom-right, near
    // the bar).
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Header: today's full date, click to jump back to it once
          //      the grid has stepped away.
          Item {
            width: parent.width
            height: headerDateText.implicitHeight

            Text {
              id: headerDateText
              textFormat: Text.PlainText
              text: labelLocale.toString(root.today, OrbitalUi.OrbitalI18n.pt ? "dddd, d 'de' MMM 'de' yyyy" : "dddd, MMM d, yyyy")
              color: heroMouse.containsMouse
                ? Style.hoverStateColor(root.contentForeground, Color.accent)
                : root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            MouseArea {
              id: heroMouse
              anchors.fill: headerDateText
              enabled: !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: tr("Back to today")
                fontFamily: root.contentFontFamily
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: root.contentForeground
            opacity: 0.12
          }

          // ---- Month stepping: the month being browsed, left-aligned,
          //      chevrons at the card's outer edge — the grid below is a
          //      read-out, so this row is the only thing that moves.
          Item {
            width: parent.width
            height: Math.max(monthLabel.implicitHeight, prevMonthButton.implicitHeight) + Style.space(6)

            Text {
              id: monthLabel
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: labelLocale.toString(root.viewDate, "MMMM yyyy")
              color: Qt.darker(root.contentForeground, 1.3)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              PanelActionButton {
                id: prevMonthButton
                iconText: "󰅁"
                tooltipText: tr("Previous month")
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                iconText: "󰅂"
                tooltipText: tr("Next month")
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero:
          //      a plain hairline said nothing, and whole days done
          //      over days in the year says the same thing louder.
          // Hidden: not in the mockup, and Column excludes invisible
          // children from its own layout automatically, so this is a
          // safe, contained way to drop it without touching the rest.
          Item {
            visible: false
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: tr("BORN")
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: tr("year")
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: 0
                  leftPadding: Style.space(6)
                  text: tr("LIVE TO")
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Memento mori. Only here once someone has gone looking and
          //      given an age; the same rail as the year above it, measured
          //      against a nominal lifetime.
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: tr("LIFE")
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: lifePercent
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.lifeDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: "Memento Mori"
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- Month grid: seven day columns, no week-number gutter (not
          //      in the mockup) — the week-start toggle this used to double
          //      as still works, just from the keyboard ('w') rather than a
          //      clickable heading cell.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              y: Style.space(10)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(6)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                Repeater {
                  model: root.weekdays

                  Text {
                    textFormat: Text.PlainText
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Repeater {
                    model: modelData.days

                    Item {
                      required property var modelData
                      width: root.cellWidth
                      height: root.cellHeight

                      Rectangle {
                        anchors.centerIn: parent
                        width: Style.space(30)
                        height: Style.space(30)
                        radius: width / 2
                        // Today is a filled badge, not an outline — the
                        // mockup's one deliberately loud mark on an
                        // otherwise quiet grid.
                        color: modelData.today ? Color.accent : "transparent"
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: modelData.day
                        color: modelData.today
                          ? Color.background
                          : (modelData.inMonth ? root.contentForeground : Qt.darker(root.contentForeground, 2.2))
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: modelData.today
                      }
                    }
                  }
                }
              }
            }
          }

          // ---- Today: real reminders (`omarchy reminder show -j`), not
          // fabricated calendar events. This system has no real
          // calendar/CalDAV backend to pull a day's meetings from, and
          // the mockup's own "Daily Standup"/"Sprint Planning" entries
          // are exactly the kind of invented data this whole project has
          // deliberately avoided elsewhere (real installed apps in the
          // dock/launcher, not the mockup's Firefox/Spotify/Notion). The
          // lightweight `omarchy reminder` tool is the one real,
          // already-existing source of "things due today" on this
          // machine — empty right now, so this section stays hidden
          // until the user actually sets one. No "View all" link either:
          // this list already is all of them, there's nowhere further to
          // send that click.
          Column {
            width: parent.width
            visible: agendaModel.count > 0
            spacing: Style.space(8)
            topPadding: Style.space(4)

            Rectangle {
              width: parent.width
              height: 1
              color: root.contentForeground
              opacity: 0.12
            }

            Text {
              text: tr("Today")
              textFormat: Text.PlainText
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Repeater {
              model: agendaModel
              delegate: Item {
                required property string label
                required property string atTime
                required property string remaining
                width: parent ? parent.width : 0
                height: Style.space(36)

                Rectangle {
                  id: eventBar
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(3)
                  height: parent.height - Style.space(4)
                  radius: width / 2
                  color: Color.accent
                }

                Text {
                  id: eventTime
                  anchors.left: eventBar.right
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(44)
                  text: atTime
                  textFormat: Text.PlainText
                  color: root.contentForeground
                  opacity: 0.55
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Column {
                  anchors.left: eventTime.right
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0

                  Text {
                    width: parent.width
                    text: label
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  Text {
                    width: parent.width
                    text: remaining.length > 0 ? tr("in ") + remaining : ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: root.contentForeground
                    opacity: 0.5
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall - 1
                  }
                }
              }
            }
          }

          ListModel { id: agendaModel }

          Process {
            id: reminderProc
            command: ["omarchy", "reminder", "show", "-j"]
            stdout: StdioCollector {
              onStreamFinished: {
                try {
                  var data = JSON.parse(text)
                  var reminders = (data && data.reminders) || []
                  agendaModel.clear()
                  for (var i = 0; i < reminders.length; i++) {
                    var r = reminders[i]
                    agendaModel.append({
                      label: String((r && r.label) || (r && r.message) || ""),
                      atTime: String((r && r.atTime) || ""),
                      remaining: String((r && r.remaining) || "")
                    })
                  }
                } catch (e) {
                }
              }
            }
            Component.onCompleted: running = true
          }

          // ---- Weather footer: real data, see the `weatherDataProc`/
          // `weatherIconProc` Processes near the panel's other Processes.
          Column {
            width: parent.width
            visible: root.weatherAvailable
            spacing: Style.space(8)
            topPadding: Style.space(4)

            Rectangle {
              width: parent.width
              height: 1
              color: root.contentForeground
              opacity: 0.12
            }

            Item {
              width: parent.width
              height: Math.max(weatherIconText.implicitHeight, weatherCityText.implicitHeight + weatherDescText.implicitHeight)

              Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Text {
                  id: weatherIconText
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.weatherIconGlyph
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: 22
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0

                  Text {
                    id: weatherCityText
                    text: root.weatherCity
                    textFormat: Text.PlainText
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  Text {
                    id: weatherDescText
                    text: root.weatherTempC + "°C  " + root.weatherDesc
                    textFormat: Text.PlainText
                    color: root.contentForeground
                    opacity: 0.6
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall - 1
                  }
                }
              }

              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "H: " + root.weatherHighC + "°C  L: " + root.weatherLowC + "°C"
                textFormat: Text.PlainText
                color: root.contentForeground
                opacity: 0.5
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall - 1
              }
            }
          }
        }
      }
    }
  }
}
