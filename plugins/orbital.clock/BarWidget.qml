import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Date/time label for the bar, split into two independently clickable
// segments (mockup: clicking the date opens a calendar, clicking the time
// opens a separate world-clock/alarms/timer/focus panel — two different
// destinations, not one combined popup). Date click opens the calendar
// (unchanged, still Panel.qml below); time click opens orbital.worldclock.
// Right click on either segment still walks the common label formats, and
// middle click still opens the timezone picker — both unchanged from the
// original single-button version this was split from.
BarWidget {
  id: root
  moduleName: "omarchy.clock"

  property date displayDate: clock.date

  readonly property string configuredFormat: vertical
    ? setting("verticalFormat", "HH\n—\nmm")
    : setting("format", "dddd HH:mm")
  readonly property string configuredAltFormat: vertical
    ? setting("verticalFormatAlt", "dd\nMMM\n'W'ww\n''yy")
    : setting("formatAlt", "d MMMM 'W'ww yyyy")

  readonly property var formatRing: Model.clockFormatRing(configuredFormat, configuredAltFormat, Model.clockFormats(vertical))

  // What the bar shows is what shell.json stores, so a cycled format is the
  // format from then on rather than something that reverts on restart.
  readonly property string activeFormat: configuredFormat
  readonly property string displayText: formatted(displayDate)
  readonly property var verticalLines: displayText.split("\n")

  // Fixed, independent of the cyclable combined format above: the two
  // segments need their own short text regardless of which combined
  // format is active, so splitting still makes sense after a right-click
  // cycle. Not user-configurable (yet) — deliberately simple.
  readonly property string dateOnlyText: Qt.formatDateTime(displayDate, "ddd, MMM d")
  readonly property string timeOnlyText: Qt.formatDateTime(displayDate, "HH:mm")

  function openWorldClock() {
    if (root.bar) root.bar.run("omarchy-shell shell toggle orbital.worldclock '{}'")
  }

  function refresh() {
    displayDate = new Date()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function cycleFormat() {
    var current = String(configuredFormat)
    var next = Model.nextClockFormat(formatRing, current)
    if (next === "" || next === current) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[vertical ? "verticalFormat" : "format"] = next

    // Applied locally first so the label changes on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function formatted(date) {
    return Qt.formatDateTime(date, activeFormat.replace(/ww/g, Model.isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate())))
  }

  // ---- Calendar popup. Shape contract for shell.summon/hide/toggle
  //      routing: Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function toggleWeekStart() {
    if (panelLoader.item) panelLoader.item.toggleWeekStart()
  }

  // The clock fills more slot than it paints a mark for, at both
  // orientations: horizontally it is a text label in a padded slot, so the
  // dot takes the label width; vertically it is a stack of icon-sized lines,
  // so the dot takes one line — the same mark every icon widget gets, rather
  // than a rule running the height of the whole stack.
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root.vertical ? button : dateButton
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: root.vertical ? button.implicitWidth : (dateButton.implicitWidth + timeButton.implicitWidth)
  implicitHeight: root.vertical ? button.implicitHeight : Math.max(dateButton.implicitHeight, timeButton.implicitHeight)

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.displayDate = date
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

  IpcHandler {
    target: "omarchy.clock"

    function refresh(): void { root.broadcast("refresh") }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // Vertical bar: unchanged, one combined stacked label — splitting a
  // narrow vertical column into two independently clickable halves isn't
  // worth the layout complexity for an orientation this install doesn't
  // use (bar.position is "bottom"/horizontal here).
  WidgetButton {
    id: button
    visible: root.vertical
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: root.verticalLines.length > 0
    fixedHeight: root.verticalLines.length * Style.bar.iconSlot
    horizontalMargin: 8.75
    verticalPadding: 8.75
    fontSize: Style.font.body + 2

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleFormat()
      else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-menu-timezone") }
      else root.togglePanel()
    }

    Column {
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3
            ? button.fontSize * 0.9
            : button.fontSize
          color: button.foreground
        }
      }
    }
  }

  // Horizontal bar: two independent segments. Date opens the calendar
  // (Panel.qml, unchanged); time opens orbital.worldclock (a fully
  // separate overlay plugin, not tracked by this widget's own
  // opened/popout state — see openWorldClock()).
  Row {
    visible: !root.vertical
    anchors.fill: parent

    WidgetButton {
      id: dateButton
      bar: root.bar
      text: root.dateOnlyText
      horizontalMargin: 8.75
      verticalPadding: 8.75
      fontSize: Style.font.body + 2
      onPressed: function(b) {
        if (b === Qt.RightButton) root.cycleFormat()
        else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-menu-timezone") }
        else root.togglePanel()
      }
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 1
      height: parent.height * 0.5
      color: button.foreground
      opacity: 0.18
    }

    WidgetButton {
      id: timeButton
      bar: root.bar
      text: root.timeOnlyText
      horizontalMargin: 8.75
      verticalPadding: 8.75
      fontSize: Style.font.body + 2
      onPressed: function(b) {
        if (b === Qt.RightButton) root.cycleFormat()
        else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-menu-timezone") }
        else root.openWorldClock()
      }
    }
  }
}
