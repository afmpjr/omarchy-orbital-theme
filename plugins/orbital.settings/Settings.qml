import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "../orbital.ui" as OrbitalUi

// Orbital Settings: setup center with sidebar, live previews and staged
// choices applied all at once. Same safe overlay shape as orbital.account.
// Pending model: sections edit pending.* only; "Apply all" runs
// orbital-settings-apply once (theme, accent, bar, widgets, keyboard,
// wallpaper, avatar, transparency, gaps, extras), then reloads Hyprland and
// restarts the shell once. Accent swatches and the lock switch stay live,
// like everywhere else they appear.

Item {
  id: root

  property bool opened: false
  property int sectionIndex: 0
  property string statusText: ""

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(1)))
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.family

  property string pAccent: "blue"
  property string pAccentCustom: ""
  property string pBar: "orbital.floating-bar"
  property string pBarPos: "bottom"
  property bool pTransparent: false
  property bool pDivider: true
  property bool pLock: true
  property string pKeyboard: "us"
  property string pWallpaper: ""
  property string pAvatarMode: "keep"
  property string pAvatarPath: ""
  property string pGaps: "8,12"
  property bool pWindowsKeys: false
  property bool pResetPins: false

  readonly property var sections: [
    { id: "accent", label: "Accent", icon: "preferences-desktop-appearance-symbolic" },
    { id: "bar", label: "Bar", icon: "emblem-system-symbolic" },
    { id: "barpos", label: "Position", icon: "pan-end-symbolic" },
    { id: "widgets", label: "Widgets", icon: "application-x-executable-symbolic" },
    { id: "keyboard", label: "Keyboard", icon: "preferences-desktop-keyboard-shortcuts-symbolic" },
    { id: "wallpaper", label: "Wallpaper", icon: "image-missing-symbolic" },
    { id: "avatar", label: "Avatar", icon: "system-lock-screen-symbolic" },
    { id: "transparency", label: "Transparency", icon: "media-playback-pause-symbolic" },
    { id: "gaps", label: "Gaps", icon: "system-reboot-symbolic" },
    { id: "extras", label: "Extras", icon: "system-shutdown-symbolic" }
  ]

  readonly property var swatches: [
    { name: "blue", color: "#39A9FF" }, { name: "indigo", color: "#3939FF" },
    { name: "purple", color: "#9539FF" }, { name: "lilac", color: "#CE39FF" },
    { name: "magenta", color: "#FF39EF" }, { name: "pink", color: "#FF39AC" },
    { name: "rose", color: "#FF395A" }, { name: "red", color: "#FF3939" },
    { name: "orange", color: "#FF8C39" }, { name: "amber", color: "#FFC439" },
    { name: "lime", color: "#ACFF39" }, { name: "green", color: "#39FF8C" },
    { name: "mint", color: "#39FFBD" }, { name: "teal", color: "#39FFEE" },
    { name: "cyan", color: "#39DEFF" }, { name: "white", color: "#FFFFFF" },
    { name: "gray", color: "#9E9E9E" }, { name: "black", color: "#0A0A0A" }
  ]

  function open(payloadJson) {
    root.opened = true
    root.statusText = ""
    lockFile.reload()
    try {
      var p = JSON.parse(payloadJson || "{}")
      if (p && p.section) {
        for (var i = 0; i < sections.length; i++) {
          if (sections[i].id === p.section) { root.sectionIndex = i; break }
        }
      }
    } catch (e) {}
  }
  function close() { root.opened = false }
  function toggle(payloadJson) { if (root.opened) root.close(); else root.open(payloadJson) }

  FileView {
    id: lockFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/orbital-widgets-lock"
    printErrors: false
    onLoaded: root.pLock = text().trim() !== "0"
    onLoadFailed: root.pLock = true
  }

  function installedPath(rel) {
    return Quickshell.env("HOME") + "/.config/omarchy/plugins/" + rel
  }

  function applyAccentLive(name) {
    root.pAccent = name
    root.pAccentCustom = ""
    Util.execDetached("python3 " + installedPath("orbital.appearance/orbital-accent.py") + " " + name)
    root.statusText = "Accent " + name + " applied."
  }

  function applyCustomHex(hex) {
    if (!/^[0-9a-fA-F]{6}$/.test(hex)) { root.statusText = "Invalid hex (6 digits)."; return }
    root.pAccentCustom = hex.toUpperCase()
    Util.execDetached("python3 " + installedPath("orbital.appearance/orbital-accent.py") + " #" + hex)
    root.statusText = "Accent #" + hex.toUpperCase() + " applied."
  }

  function toggleLockLive() {
    Util.execDetached(installedPath("orbital.account/orbital-widgets-lock") + " --toggle")
    lockRefresh.restart()
  }

  Timer {
    id: lockRefresh
    interval: 600
    repeat: false
    onTriggered: lockFile.reload()
  }

  function applyAll() {
    root.statusText = "Applying..."
    applyProc.command = [
      installedPath("orbital.settings/orbital-settings-apply"),
      root.pAccentCustom.length > 0 ? ("#" + root.pAccentCustom) : root.pAccent,
      root.pBar, root.pBarPos, root.pTransparent ? "true" : "false",
      root.pDivider ? "true" : "false", root.pLock ? "true" : "false",
      root.pKeyboard, root.pWallpaper, root.pAvatarMode, root.pAvatarPath,
      root.pGaps, root.pWindowsKeys ? "true" : "false",
      root.pResetPins ? "true" : "false"
    ]
    applyProc.running = true
  }

  Process {
    id: applyProc
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line || "").trim()
        if (s.length > 0) root.statusText = s
      }
    }
    onExited: function(code) {
      if (code !== 0 && root.statusText === "Applying...") root.statusText = "Failed (code " + code + ")."
    }
  }

  property var wallpapers: []
  property var pendingWalls: []
  Process {
    id: wallScan
    command: ["bash", "-c", 'd1="$HOME/.config/omarchy/themes/orbital/backgrounds"; d2="$HOME/Pictures"; for d in "$d1" "$d2"; do [[ -d $d ]] && find "$d" -maxdepth 2 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \\) 2>/dev/null; done | head -8']
    stdout: SplitParser {
      onRead: function(line) {
        var v = String(line || "").trim()
        if (v.length > 0) root.pendingWalls.push(v)
      }
    }
    onStarted: root.pendingWalls = []
    onExited: root.wallpapers = root.pendingWalls
  }

  component SideRow: Rectangle {
    id: sideRow
    required property string label
    required property string iconName
    property int rowIdx: -1
    signal activated()
    width: parent ? parent.width : 0
    height: Style.space(34)
    radius: Style.space(8)
    color: root.sectionIndex === rowIdx
      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
      : (sideMouse.containsMouse
        ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent")
    Row {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(10)
      Image {
        width: Style.space(16)
        height: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        fillMode: Image.PreserveAspectFit
        source: OrbitalUi.OrbitalIcons.file(sideRow.iconName)
      }
      Text {
        width: parent.width - Style.space(46)
        anchors.verticalCenter: parent.verticalCenter
        text: sideRow.label
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
    MouseArea {
      id: sideMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: sideRow.activated()
    }
  }

  component OptionRow: Rectangle {
    id: optRow
    required property string label
    property string sub: ""
    property bool selected: false
    property bool isSwitch: false
    property bool switchOn: false
    signal activated()
    width: parent ? parent.width : 0
    height: optSub.visible ? Style.space(52) : Style.space(38)
    radius: Style.space(8)
    color: optRow.selected
      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
      : (optMouse.containsMouse
        ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent")
    border.width: optRow.selected ? 2 : 0
    border.color: Color.accent
    Column {
      anchors.left: parent.left
      anchors.right: switchWidget.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      spacing: 0
      Text {
        width: parent.width
        text: optRow.label
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
      Text {
        id: optSub
        width: parent.width
        visible: optRow.sub.length > 0
        text: optRow.sub
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Math.max(7, Style.font.bodySmall - 3)
        elide: Text.ElideRight
      }
    }
    Rectangle {
      id: switchWidget
      visible: optRow.isSwitch
      width: Style.space(38)
      height: Style.space(22)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      radius: height / 2
      color: optRow.switchOn ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
      Behavior on color { ColorAnimation { duration: 120 } }
      Rectangle {
        width: Style.space(16)
        height: Style.space(16)
        radius: width / 2
        color: "white"
        anchors.verticalCenter: parent.verticalCenter
        x: optRow.switchOn ? parent.width - width - 3 : 3
        Behavior on x { NumberAnimation { duration: 120 } }
      }
    }
    MouseArea {
      id: optMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: optRow.activated()
    }
  }

  component SectionTitle: Text {
    required property string label
    text: label
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
  }

  component SwatchButton: Rectangle {
    id: swBtn
    required property string swName
    required property color swColor
    signal activated()
    width: Style.space(30)
    height: Style.space(30)
    radius: width / 2
    color: swBtn.swColor
    border.width: root.pAccent === swBtn.swName && root.pAccentCustom.length === 0 ? 3 : 1
    border.color: root.pAccent === swBtn.swName && root.pAccentCustom.length === 0
      ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3)
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: swBtn.activated()
    }
  }

  component ThumbButton: Rectangle {
    id: thBtn
    required property string filePath
    property bool selected: false
    signal activated()
    width: 104
    height: 64
    radius: Style.space(8)
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
    border.width: thBtn.selected ? 2 : 1
    border.color: thBtn.selected ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
    clip: true
    Image {
      anchors.fill: parent
      source: Util.fileUrl(thBtn.filePath)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
    }
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: thBtn.activated()
    }
  }

  component BarMock: Item {
    id: barMock
    width: parent ? parent.width : 0
    height: 84
    Rectangle {
      anchors.fill: parent
      radius: Style.space(8)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
    }
    Rectangle {
      id: mockBar
      height: 22
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: root.pBar === "orbital.floating-bar" ? 18 : 0
      anchors.rightMargin: root.pBar === "orbital.floating-bar" ? 18 : 0
      anchors.top: root.pBarPos === "top" ? parent.top : undefined
      anchors.bottom: root.pBarPos === "bottom" ? parent.bottom : undefined
      color: Color.accent
      opacity: root.pTransparent ? 0.35 : 0.85
      radius: 6
      Row {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 4
        Rectangle { width: 26; height: 14; radius: 3; color: Qt.rgba(255, 255, 255, 0.85) }
        Rectangle { width: 14; height: 14; radius: 3; color: Qt.rgba(255, 255, 255, 0.6) }
        Rectangle { width: 14; height: 14; radius: 3; color: Qt.rgba(255, 255, 255, 0.6) }
        Item { width: 8; height: 14 }
        Rectangle {
          width: 30; height: 14; radius: 3
          color: Qt.rgba(255, 255, 255, 0.75)
          visible: root.pDivider
        }
        Rectangle { width: 20; height: 14; radius: 3; color: Qt.rgba(255, 255, 255, 0.6) }
      }
    }
    Text {
      anchors.top: mockBar.bottom
      anchors.topMargin: 2
      anchors.horizontalCenter: parent.horizontalCenter
      text: (root.pBar === "orbital.floating-bar" ? "floating" : "full width")
        + " · " + root.pBarPos + (root.pTransparent ? " · transparent" : " · solid")
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Math.max(7, Style.font.bodySmall - 3)
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "orbital-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Item {
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
      }
    }

    BorderSurface {
      id: card
      width: Style.space(720)
      height: Style.space(520)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      Column {
        id: mainCol
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(10)

        Text {
          id: headerText
          text: "Orbital Settings"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Row {
          id: contentRow
          width: parent.width
          height: parent.height - headerText.height - footerRow.height - mainCol.spacing * 2
          spacing: Style.space(12)

          Column {
            id: sidebar
            width: Style.space(190)
            height: parent.height
            spacing: Style.space(2)
            Repeater {
              model: root.sections
              SideRow {
                required property var modelData
                required property int index
                label: modelData.label
                iconName: modelData.icon
                rowIdx: index
                onActivated: root.sectionIndex = index
              }
            }
          }

          Rectangle {
            width: 1
            height: parent.height
            color: root.foreground
            opacity: 0.12
          }

          Item {
            id: contentArea
            width: parent.width - sidebar.width - 1 - parent.spacing * 2
            height: parent.height

            Item {
              anchors.fill: parent
              visible: root.sectionIndex === 0
              Column {
                anchors.fill: parent
                spacing: Style.space(8)
                SectionTitle { label: "Accent color (applies live)" }
                Grid {
                  columns: 9
                  columnSpacing: Style.space(8)
                  rowSpacing: Style.space(8)
                  Repeater {
                    model: root.swatches
                    SwatchButton {
                      required property var modelData
                      swName: modelData.name
                      swColor: modelData.color
                      onActivated: root.applyAccentLive(swName)
                    }
                  }
                }
                Row {
                  spacing: Style.space(8)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Custom #"
                    textFormat: Text.PlainText
                    color: root.foreground
                    opacity: 0.6
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Rectangle {
                    width: 110
                    height: Style.space(30)
                    radius: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                    TextInput {
                      id: hexInput
                      anchors.fill: parent
                      anchors.leftMargin: 8
                      verticalAlignment: TextInput.AlignVCenter
                      maximumLength: 6
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      color: root.foreground
                      onAccepted: root.applyCustomHex(text)
                    }
                  }
                }
              }
            }

            Item {
              anchors.fill: parent
              visible: root.sectionIndex === 1
              Column {
                anchors.fill: parent
                spacing: Style.space(8)
                SectionTitle { label: "Bar" }
                BarMock {}
                OptionRow {
                  label: "orbital.floating-bar"
                  sub: "Floating, the theme default"
                  selected: root.pBar === "orbital.floating-bar"
                  onActivated: root.pBar = "orbital.floating-bar"
                }
                OptionRow {
                  label: "orbital.bar"
                  sub: "Full width, the alternative"
                  selected: root.pBar === "orbital.bar"
                  onActivated: root.pBar = "orbital.bar"
                }
              }
            }

            Item {
              anchors.fill: parent
              visible: root.sectionIndex === 2
              Column {
                anchors.fill: parent
                spacing: Style.space(8)
                SectionTitle { label: "Bar position" }
                BarMock {}
                OptionRow { label: "Bottom"; selected: root.pBarPos === "bottom"; onActivated: root.pBarPos = "bottom" }
                OptionRow { label: "Top"; selected: root.pBarPos === "top"; onActivated: root.pBarPos = "top" }
                OptionRow { label: "Left"; selected: root.pBarPos === "left"; onActivated: root.pBarPos = "left" }
                OptionRow { label: "Right"; selected: root.pBarPos === "right"; onActivated: root.pBarPos = "right" }
              }
            }

            Item {
              anchors.fill: parent
              visible: root.sectionIndex === 3
              Column {
                anchors.fill: parent
                spacing: Style.space(8)
                SectionTitle { label: "Widgets" }
                OptionRow {
                  label: root.pLock ? "Widgets locked" : "Widgets unlocked"
                  sub: "Locks bar rearranging (applies live)"
                  isSwitch: true
                  switchOn: root.pLock
                  onActivated: root.toggleLockLive()
                }
                OptionRow {
                  label: "Divider on the bar"
                  sub: "Hairline between keyboard and clock"
                  isSwitch: true
                  switchOn: root.pDivider
                  onActivated: root.pDivider = !root.pDivider
                }
              }
            }

            Item {
              anchors.fill: parent
              visible: root.sectionIndex === 4
              Column {
                anchors.fill: parent
                spacing: Style.space(8)
                SectionTitle { label: "Keyboard" }
                OptionRow { label: "us"; sub: "US only"; selected: root.pKeyboard === "us"; onActivated: root.pKeyboard = "us" }
                OptionRow { label: "us,br"; sub: "Alt+Shift switches"; selected: root.pKeyboard === "us,br"; onActivated: root.pKeyboard = "us,br" }
                OptionRow { label: "br,us"; sub: "BR default, Alt+Shift switches"; selected: root.pKeyboard === "br,us"; onActivated: root.pKeyboard = "br,us" }
              }
            }

            Item {
              anchors.fill: parent
              visible: root.sectionIndex === 5
              Column {
                anchors.fill: parent
                spacing: Style.space(8)
                SectionTitle { label: "Wallpaper" }
                OptionRow {
                  label: "Keep current"
                  selected: root.pWallpaper.length === 0
                  onActivated: root.pWallpaper = ""
                }
                Grid {
                  columns: 4
                  columnSpacing: Style.space(8)
                  rowSpacing: Style.space(8)
                  Repeater {
                    model: root.wallpapers
                    ThumbButton {
                      required property var modelData
                      filePath: String(modelData)
                      selected: root.pWallpaper === String(modelData)
                      onActivated: root.pWallpaper = String(modelData)
                    }
                  }
                }
              }
            }

            Item {
              anchors.fill: parent
              visible: root.sectionIndex === 6
              Column {
                anchors.fill: parent
                spacing: Style.space(8)
                SectionTitle { label: "Avatar" }
                OptionRow { label: "Keep"; selected: root.pAvatarMode === "keep"; onActivated: root.pAvatarMode = "keep" }
                OptionRow { label: "GitHub photo"; sub: "Needs gh auth login"; selected: root.pAvatarMode === "github"; onActivated: root.pAvatarMode = "github" }
                OptionRow { label: "Remove avatar"; selected: root.pAvatarMode === "clear"; onActivated: root.pAvatarMode = "clear" }
                OptionRow { label: "File..."; sub: root.pAvatarPath.length > 0 ? root.pAvatarPath : "Image path"; selected: root.pAvatarMode === "file"; onActivated: root.pAvatarMode = "file" }
                Rectangle {
                  visible: root.pAvatarMode === "file"
                  width: parent.width
                  height: Style.space(30)
                  radius: Style.space(8)
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                  border.width: 1
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                  TextInput {
                    id: avatarPathInput
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    color: root.foreground
                    onTextChanged: root.pAvatarPath = text
                  }
                }
              }
            }

            Item {
              anchors.fill: parent
              visible: root.sectionIndex === 7
              Column {
                anchors.fill: parent
                spacing: Style.space(8)
                SectionTitle { label: "Bar transparency" }
                BarMock {}
                OptionRow {
                  label: "Transparent bar"
                  isSwitch: true
                  switchOn: root.pTransparent
                  onActivated: root.pTransparent = !root.pTransparent
                }
              }
            }

            Item {
              anchors.fill: parent
              visible: root.sectionIndex === 8
              Column {
                anchors.fill: parent
                spacing: Style.space(8)
                SectionTitle { label: "Window gaps" }
                OptionRow { label: "Default"; sub: "8/12, the author's"; selected: root.pGaps === "8,12"; onActivated: root.pGaps = "8,12" }
                OptionRow { label: "Compact"; sub: "4/4"; selected: root.pGaps === "4,4"; onActivated: root.pGaps = "4,4" }
                OptionRow { label: "No gaps"; sub: "0, all tiled"; selected: root.pGaps === "0,0"; onActivated: root.pGaps = "0,0" }
              }
            }

            Item {
              anchors.fill: parent
              visible: root.sectionIndex === 9
              Column {
                anchors.fill: parent
                spacing: Style.space(8)
                SectionTitle { label: "Extras" }
                OptionRow {
                  label: "Windows-style shortcuts"
                  sub: "Super+R, Super+E and friends (opt-in)"
                  isSwitch: true
                  switchOn: root.pWindowsKeys
                  onActivated: root.pWindowsKeys = !root.pWindowsKeys
                }
                OptionRow {
                  label: "Reset dock pins"
                  sub: "Back to default pins on next apply"
                  selected: root.pResetPins
                  onActivated: root.pResetPins = !root.pResetPins
                }
              }
            }
          }
        }

        Row {
          id: footerRow
          width: parent.width
          spacing: Style.space(10)
          Text {
            width: parent.width - applyButton.width - closeButton.width - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusText
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
          Rectangle {
            id: closeButton
            width: 90
            height: Style.space(34)
            radius: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            color: closeMouse.containsMouse
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3)
            Text {
              anchors.centerIn: parent
              text: "Close"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.close()
            }
          }
          Rectangle {
            id: applyButton
            width: 130
            height: Style.space(34)
            radius: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            color: Color.accent
            Text {
              anchors.centerIn: parent
              text: "Apply all"
              textFormat: Text.PlainText
              color: Color.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.applyAll()
            }
          }
        }
      }
    }
  }
}
