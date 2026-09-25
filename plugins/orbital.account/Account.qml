// Orbital Account — the mockup's profile/account panel: avatar, the real
// system user's name/email (git config, not hardcoded — see below), a
// short list of settings links that actually go somewhere real, and the
// four power actions.
//
// Real data sources, none invented:
//   - Avatar: same file orbital.dock's own avatar uses
//     (~/.config/omarchy/avatar.png), same Quickshell.iconPath fallback.
//   - Name/email: the identity cache below (`identity.json`), falling back
//     to `git config --global user.name`/`user.email` read via a real
//     Process at open() time. Nothing is hardcoded; the mockup's
//     placeholder name is not used.
//   - Settings links only cover items with a real destination on this
//     system (confirmed via `omarchy commands`): Appearance opens the
//     orbital.appearance color window (which links on to the theme menu),
//     Keyboard Shortcuts opens
//     the real keybindings search (`omarchy-menu-keybindings`, what
//     SUPER+K already runs). The mockup's other rows (Account Settings,
//     Notifications, Privacy & Security, My Profile) have no equivalent
//     first-party surface found in `omarchy commands` — left out rather
//     than wired to nothing.
//   - Power actions: `omarchy system lock/reboot/shutdown` (real,
//     documented commands) and `systemctl suspend` for Sleep (no
//     `omarchy system sleep`/suspend command exists — this is the
//     standard systemd-logind call every other DE's power menu uses).
//
// Same safe popup pattern as orbital.dock's context menu/tooltip
// (PanelWindow + static WlrKeyboardFocus.Exclusive, visible: opened) —
// see Dock.qml's header for why that shape, not KeyboardPanel's, is the
// one proven not to risk the session-freeze bug from earlier in this
// project.

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
  property string userName: ""
  property string userEmail: ""

  readonly property string avatarSource: Util.fileUrl(Quickshell.env("HOME") + "/.config/omarchy/avatar.png")

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(1)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.family
  property int panelWidth: Style.space(280)

  function open(payloadJson) {
    root.opened = true
    identityFile.reload()
  }

  function close() {
    root.opened = false
  }

  function toggle(payloadJson) {
    if (root.opened) root.close()
    else root.open(payloadJson)
  }

  function run(command) {
    root.close()
    Util.execDetached(command)
  }

  // Real name/email, same source the lock screen (a lock-screen plugin) uses:
  // ~/.local/state/omarchy/identity.json, refreshed by
  // `omarchy-refresh-identity` (real GitHub profile via `gh api user` when
  // authenticated, falling back to `git config --global user.name/email`
  // or $USER — never fabricated). Reading a cached file rather than
  // calling `gh` live keeps this panel fast and offline-safe; the git
  // config Process below only runs if the cache doesn't exist yet (e.g.
  // `omarchy-refresh-identity` was never run on this machine).
  FileView {
    id: identityFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/identity.json"
    watchChanges: false
    printErrors: false
    onLoaded: {
      try {
        var data = JSON.parse(text())
        root.userName = String((data && data.name) || "")
        root.userEmail = String((data && data.email) || "")
      } catch (e) {
      }
      if (root.userName.length === 0) identityProc.running = true
    }
    onLoadFailed: identityProc.running = true
  }

  Process {
    id: identityProc
    command: ["bash", "-c", "git config --global user.name; echo '---'; git config --global user.email"]
    property string buffer: ""
    stdout: SplitParser {
      onRead: function(line) {
        if (line === "---") return
        if (identityProc.buffer === "") identityProc.buffer = line
        else root.userEmail = line
      }
    }
    onStarted: { buffer = ""; root.userName = ""; root.userEmail = "" }
    onExited: root.userName = identityProc.buffer || Quickshell.env("USER") || ""
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "orbital-account"
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
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
      }
    }

    BorderSurface {
      id: card
      width: root.panelWidth
      // Fixed, not content.implicitHeight-derived: that binding read the
      // Column's implicitHeight before its own children (built off
      // card.contentTopInset/contentLeftInset, which this card itself
      // provides) had settled on the first frame, so the card collapsed
      // to near-zero height and the whole panel rendered as a sliver
      // clipped at the very bottom of the screen. A fixed height, same
      // pattern orbital.launcher's own card already uses successfully,
      // sidesteps the circular first-frame sizing dependency entirely.
      height: Style.space(360)
      radius: root.cornerRadius
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.space(12)
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
        spacing: Style.space(4)

        // Header — avatar, real name, real email, settings glyph.
        Item {
          width: parent.width
          height: Style.space(44)

          Row {
            anchors.left: parent.left
            anchors.right: settingsGlyph.left
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(10)

            Image {
              width: Style.space(44)
              height: Style.space(44)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              source: root.avatarSource
              visible: status === Image.Ready
            }

            Column {
              width: parent.width - Style.space(54)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.userName.length > 0 ? root.userName : Quickshell.env("USER")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                width: parent.width
                visible: root.userEmail.length > 0
                text: root.userEmail
                textFormat: Text.PlainText
                elide: Text.ElideRight
                opacity: 0.6
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Image {
            id: settingsGlyph
            anchors.right: parent.right
            anchors.top: parent.top
            width: Style.space(16)
            height: Style.space(16)
            fillMode: Image.PreserveAspectFit
            opacity: 0.5
            source: Quickshell.iconPath("emblem-system-symbolic", true)

            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(6)
              cursorShape: Qt.PointingHandCursor
              onClicked: root.run("omarchy-menu toggle theme")
            }
          }
        }

        Item { width: 1; height: Style.space(6) }

        Rectangle {
          width: parent.width
          height: 1
          color: root.foreground
          opacity: 0.12
        }

        // A single reusable row for settings links: icon, label, chevron.
        component LinkRow: Rectangle {
          id: linkRow
          required property string label
          required property string iconName
          property bool showChevron: true
          signal activated()

          width: parent ? parent.width : 0
          height: Style.space(38)
          radius: Style.space(8)
          color: linkMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"

          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(10)

            Image {
              width: Style.space(18)
              height: Style.space(18)
              anchors.verticalCenter: parent.verticalCenter
              fillMode: Image.PreserveAspectFit
              source: Quickshell.iconPath(linkRow.iconName, true)
            }

            Text {
              width: parent.width - Style.space(46)
              anchors.verticalCenter: parent.verticalCenter
              text: linkRow.label
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Image {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(14)
            height: Style.space(14)
            fillMode: Image.PreserveAspectFit
            opacity: 0.4
            visible: linkRow.showChevron
            source: Quickshell.iconPath("pan-end-symbolic", true)
          }

          MouseArea {
            id: linkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: linkRow.activated()
          }
        }

        LinkRow {
          label: "Appearance"
          iconName: "preferences-desktop-theme"
          onActivated: { root.close(); Util.execDetached("omarchy-shell shell toggle orbital.appearance '{}'") }
        }

        LinkRow {
          label: "Keyboard Shortcuts"
          iconName: "preferences-desktop-keyboard-shortcuts"
          onActivated: root.run("omarchy-menu-keybindings")
        }

        Item {
          width: parent.width
          height: Style.space(6) + 1

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: root.foreground
            opacity: 0.12
          }
        }

        // Power actions — Lock / Sleep / Restart / Shut Down, as a
        // vertical list matching the mockup (same row language as
        // Appearance/Keyboard Shortcuts above, just no chevron since
        // these act immediately instead of navigating anywhere).
        Column {
          width: parent.width

          LinkRow {
            label: "Lock"; iconName: "system-lock-screen"; showChevron: false
            onActivated: root.run("omarchy system lock")
          }
          LinkRow {
            label: "Sleep"; iconName: "preferences-system-power"; showChevron: false
            onActivated: root.run("systemctl suspend")
          }
          LinkRow {
            label: "Restart"; iconName: "system-reboot"; showChevron: false
            onActivated: root.run("omarchy system reboot")
          }
          LinkRow {
            label: "Shut Down"; iconName: "system-shutdown"; showChevron: false
            onActivated: root.run("omarchy system shutdown")
          }
        }
      }
    }
  }
}
