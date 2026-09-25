import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import Quickshell.Wayland
import "KeyboardModel.js" as KeyboardLayoutModel

BarWidget {
  id: root
  moduleName: "orbital.keyboard"


  property string layoutFull: ""
  // The keyboard the last reading spoke for, which is the one a click switches,
  // and separately the one activelayout named as being typed on. A reading
  // confirms the first is really there, so the click has a keyboard to reach
  // from the first reading onwards rather than only after a switch, and stops
  // naming one that has been unplugged.
  property string keyboardName: ""
  property string typedKeyboardName: ""
  // Keyboards on the seat, buttons and virtual ones excluded, and whether the
  // last reading left that shape in doubt.
  property int keyboardCount: 0
  property bool keyboardUnresolved: false
  // Nothing to read or switch on the single-layout install most people run, so
  // the widget ships on the bar and stays out of the way until there are two.
  // An older Hyprland that doesn't report the list keeps showing the label.
  property bool multipleLayouts: true
  // Short language code per layout description ("English (US)": "en"), read from
  // xkb's own table rather than maintained by hand.
  property var layoutBriefs: ({})
  property var layoutDescriptions: ({})
  property var keyboardInfo: null
  property bool menuOpen: false
  property int menuFocus: 0
  readonly property var layouts: KeyboardLayoutModel.layoutList(keyboardInfo, layoutDescriptions, layoutBriefs)
  readonly property int activeIndex: keyboardInfo && keyboardInfo.active_layout_index ? keyboardInfo.active_layout_index : 0
  // Alt+Shift works either through xkb's option or through install.sh's release binds
  // (~/.config/hypr/orbital-keyboard.lua); show the hint when one of them is in place.
  readonly property bool altShiftToggle: orbitalKeyboardFile.loaded
    || (keyboardInfo && String(keyboardInfo.options || "").indexOf("grp:alt_shift_toggle") !== -1)

  FileView {
    id: orbitalKeyboardFile
    path: Quickshell.env("HOME") + "/.config/hypr/orbital-keyboard.lua"
    printErrors: false
    watchChanges: false
  }
  readonly property string layoutLabel: KeyboardLayoutModel.shortLabel(layoutFull, layoutBriefs)

  // A query already in flight was started before this event, so it may read the
  // layout the switch replaced. Remember the request and re-run once it lands
  // rather than dropping it; nothing else would correct the label afterwards.
  property bool refreshPending: false

  function refresh() {
    if (queryProc.running) {
      refreshPending = true
      return
    }

    refreshPending = false
    queryProc.running = true
  }

  // Keyboards someone can actually type on, which is not everything Hyprland
  // calls a keyboard.
  function typedKeyboards(keyboards) {
    return keyboards.filter(k => KeyboardLayoutModel.isTypedKeyboard(k.name))
  }

  // The main flag names no keyboard for long: fcitx5 takes it with the virtual
  // keyboard it binds to inject, which leaves no typed keyboard holding it and
  // nothing to read at all, and once that unbinds it lands on whichever device
  // Hyprland saw last, a power button included. Go by layout progress instead,
  // and by the keyboard activelayout named.
  function selectKeyboard(typed) {
    return KeyboardLayoutModel.selectKeyboard(typed, root.typedKeyboardName)
  }

  // switchxkblayout is a hyprctl command rather than a dispatcher, so it has to
  // be run rather than sent over the dispatch socket. It switches the keyboard
  // the last reading spoke for, so a click always advances the device the label
  // is describing. Switching the seat together would reach the typed keyboard
  // without having to name it, but it would also carry the buttons along, and
  // the whole read depends on those staying where they started: once a button
  // has been advanced too, a toggle that wraps the keyboard back to the first
  // layout leaves the button reading as the furthest along, and the label
  // follows the button.
  // Applied to every keyboard on the seat (an explicit index, so they all end up on the same
  // layout): with keyd or fcitx5 the typed events come from a virtual keyboard, not the one
  // that was read.
  function setLayout(index) {
    if (!root.bar) return
    root.bar.run("hyprctl switchxkblayout all " + index)
    root.menuOpen = false
    refreshTimer.restart()
  }

  // Shape contract for `omarchy-shell shell toggle orbital.keyboard` (open/close/opened on the
  // widget root, like the calendar): lets a hotkey or a script open the dropdown.
  readonly property bool opened: root.menuOpen
  function open() { root.menuOpen = true; root.menuFocus = root.activeIndex }
  function close() { root.menuOpen = false }
  function toggle(payload) { if (root.menuOpen) root.close(); else root.open() }

  function toggleMenu() {
    root.menuOpen = !root.menuOpen
    if (root.menuOpen) root.menuFocus = root.activeIndex
  }

  function cycleLayout() {
    if (!root.keyboardName || !root.bar) return
    root.bar.run("hyprctl switchxkblayout " + Util.shellQuote(root.keyboardName) + " next")
    refreshTimer.restart()
  }

  Component.onCompleted: {
    briefsProc.running = true
    refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      // The event names the keyboard that switched ahead of the layout it moved
      // to, and that is the keyboard being typed on whatever holds the main flag.
      if (name === "activelayout") {
        const named = KeyboardLayoutModel.eventKeyboardName(event)
        if (named) root.typedKeyboardName = named
      }

      // A reload that adds a layout to kb_layout decides whether the widget
      // shows at all, and leaves every keyboard on the layout it was already
      // reading, so it raises no activelayout to notice it by.
      if (name.indexOf("activelayout") !== -1 || name === "configreloaded") root.refresh()
    }
  }

  Process {
    id: queryProc
    command: ["hyprctl", "-j", "devices"]
    onRunningChanged: {
      if (running) {
        stallTimer.restart()
        return
      }

      stallTimer.stop()
      if (root.refreshPending) root.refresh()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        let listed
        try {
          listed = JSON.parse(text || "{}").keyboards
        } catch (e) {
          return
        }

        // A query the watchdog killed reports nothing at all, and an empty
        // string parses into the same shape a seat with no keyboards would.
        // Tell them apart by the list itself, so only a reading that reached
        // hyprctl gets to speak for the seat.
        if (!Array.isArray(listed)) return

        const typed = root.typedKeyboards(listed)
        const kb = root.selectKeyboard(typed)
        if (!kb || !kb.active_keymap) {
          // Either the last keyboard has been unplugged, which the label has to
          // stop describing and the click has to stop naming, or keyboards are
          // there and none of them reports a keymap. Both leave the shape in
          // doubt, so keep asking rather than letting a count from before it
          // changed settle the poll.
          root.keyboardUnresolved = true
          if (typed.length === 0) {
            root.layoutFull = ""
            root.keyboardName = ""
          }
          return
        }

        root.keyboardUnresolved = false
        root.keyboardCount = typed.length
        root.keyboardName = String(kb.name || "")
        root.multipleLayouts = kb.layout === undefined || String(kb.layout).indexOf(",") !== -1
        root.layoutFull = kb.active_keymap
        root.keyboardInfo = kb
      }
    }
  }

  // The table only changes when xkb data is upgraded, so read it at startup and
  // leave it alone. The bar is built per monitor, so this runs once per widget.
  // The exotic rulesets cover layouts like trans (IPA) that ship in the same xkb
  // package and set just as well, so load them or those labels lose their code.
  Process {
    id: briefsProc
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.layoutBriefs = KeyboardLayoutModel.layoutBriefs(text)
        root.layoutDescriptions = KeyboardLayoutModel.layoutDescriptions(text)
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: 600
    onTriggered: root.refresh()
  }

  // A query that never returns would freeze the label until the shell restarts,
  // since a Process that is already running can't be re-run. Give up on one that
  // overstays so the next refresh gets through, and ask again: the reading it
  // never delivered may have been the only one due on a settled seat, and
  // nothing else would come back for it.
  Timer {
    id: stallTimer
    interval: 5000
    onTriggered: {
      queryProc.running = false
      refreshTimer.restart()
    }
  }

  // Which keyboard on a crowded seat the label is describing can change without
  // Hyprland announcing it, since a device arriving or leaving raises no event
  // of its own, and that can only be learned by asking. Poll while there is that
  // ambiguity, until a first reading lands so a query that failed at login still
  // recovers, and while a reading has left the seat's shape in doubt. The
  // one-keyboard install has none of those, and is left alone rather than
  // spawning hyprctl forever for an answer that cannot change.
  Timer {
    interval: 10000
    running: !root.keyboardName || root.keyboardUnresolved || root.keyboardCount > 1
    repeat: true
    onTriggered: root.refresh()
  }

  visible: layoutLabel !== "" && multipleLayouts
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The active layout's country flag (flag-icons, MIT; see flags/ and LICENSE-flag-icons).
  // Layouts without a flag (Arabic, Latin American, ...) fall back to the text label.
  readonly property string activeCode: root.layouts.length > root.activeIndex ? root.layouts[root.activeIndex].code : ""

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.layoutLabel
    labelVisible: flagImage.status !== Image.Ready
    fixedWidth: flagImage.status === Image.Ready ? Style.space(34) : -1
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: root.layoutFull
    onPressed: function() { root.toggleMenu() }

    Image {
      id: flagImage
      anchors.centerIn: parent
      width: Style.space(20)
      height: Math.round(width * 3 / 4)
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      source: root.activeCode !== "" ? Qt.resolvedUrl("flags/" + root.activeCode + ".svg") : ""
      visible: status === Image.Ready
    }
  }

  // Dropdown: same KeyboardPanel the dock menu and the calendar use, so it
  // renders above windows and anchors to this button.
  KeyboardPanel {
    id: menu
    anchorItem: button
    owner: ({ close: function() { root.menuOpen = false } })
    bar: root.bar
    open: root.menuOpen
    centerOnBar: false
    focusTarget: menuKeys
    contentWidth: menu.fittedContentWidth(Style.space(270))
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)

    Item {
      id: menuKeys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        var n = root.layouts.length
        if (event.key === Qt.Key_Escape) { root.menuOpen = false; event.accepted = true }
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { root.menuFocus = (root.menuFocus + 1) % Math.max(1, n); event.accepted = true }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { root.menuFocus = (root.menuFocus + n - 1) % Math.max(1, n); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.setLayout(root.menuFocus); event.accepted = true }
      }

      Column {
        id: menuColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(2)

        Repeater {
          model: root.layouts

          Rectangle {
            id: row
            required property var modelData
            readonly property bool current: modelData.index === root.activeIndex
            width: menuColumn.width
            height: Style.space(32)
            radius: Style.space(8)
            color: rowMouse.containsMouse || root.menuFocus === modelData.index
                   ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

            Text {
              id: check
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(14)
              text: row.current ? "\u2713" : ""
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            Item {
              id: flagSlot
              anchors.left: check.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(34)
              height: parent.height

              Image {
                id: rowFlag
                anchors.centerIn: parent
                width: Style.space(22)
                height: Math.round(width * 3 / 4)
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                source: Qt.resolvedUrl("flags/" + modelData.code + ".svg")
                visible: status === Image.Ready
              }
              Text {
                anchors.centerIn: parent
                visible: rowFlag.status !== Image.Ready
                text: modelData.label
                color: row.current ? Color.accent : (root.bar ? root.bar.foreground : Color.foreground)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }
            Text {
              anchors.left: flagSlot.right
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.description
              elide: Text.ElideRight
              color: root.bar ? root.bar.foreground : Color.foreground
              opacity: row.current ? 1 : 0.75
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setLayout(modelData.index)
            }
          }
        }

        Text {
          visible: root.altShiftToggle
          width: menuColumn.width
          topPadding: Style.space(6)
          horizontalAlignment: Text.AlignHCenter
          text: "Alt + Shift to switch"
          color: root.bar ? root.bar.foreground : Color.foreground
          opacity: 0.45
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
