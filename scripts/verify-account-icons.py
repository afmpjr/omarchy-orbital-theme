#!/usr/bin/env python3
"""Temporary: prove OrbitalIcons resolves real files, and that the path QML gets
is one a QML Image can actually load. Reverts itself from /tmp/Account.bak.

Run with --install to patch the guest-facing Account.qml in the repo, then
scripts/verify-account-icons.sh deploys, restarts the shell and prints the report.
"""
import sys

P = "plugins/orbital.account/Account.qml"
MARK = "  // TEMP DIAG"

DIAG = '''  // TEMP DIAG
  readonly property var _dn: ["preferences-desktop-appearance-symbolic", "preferences-desktop-keyboard-shortcuts-symbolic", "system-lock-screen-symbolic", "media-playback-pause-symbolic", "system-reboot-symbolic", "system-shutdown-symbolic", "pan-end-symbolic", "emblem-system-symbolic", "totally-fake-name-xyz"]
  // The icon scan is asynchronous, so the report has to wait for it: writing on
  // Component.onCompleted records an empty index and proves nothing.
  Timer {
    id: _dt
    interval: 6000
    running: true
    repeat: false
    onTriggered: _dp.running = true
  }
  Process {
    id: _dp
    command: ["bash", "-c", "printf '%s\\\\n' \\"$1\\" > /tmp/acc-diag.txt", "sh", root._dr()]
  }
  function _dr() {
    var o = []
    for (var i = 0; i < _dn.length; i++) {
      var p = root.iconSource(_dn[i])
      o.push(_dn[i] + " => [" + p + "] len=" + p.length)
    }
    o.push("index size=" + Object.keys(OrbitalUi.OrbitalIcons.index).length + " ready=" + OrbitalUi.OrbitalIcons.ready)
    o.push("---")
    o.push("input-keyboard-symbolic => [" + root.iconSource("input-keyboard-symbolic") + "]")
    o.push("applications-graphics-symbolic => [" + root.iconSource("applications-graphics-symbolic") + "]")
    return o.join("\\n")
  }

  function iconSource(name) {'''


def install():
    src = open(P).read()
    if MARK in src:
        print("already instrumented")
        return
    if "function iconSource(name) {" not in src:
        sys.exit("anchor not found")
    open("/tmp/Account.bak", "w").write(src)
    open(P, "w").write(src.replace("  function iconSource(name) {", DIAG, 1))
    print("instrumented; backup at /tmp/Account.bak")


def revert():
    try:
        open(P, "w").write(open("/tmp/Account.bak").read())
        print("reverted")
    except FileNotFoundError:
        print("no backup to revert")


if __name__ == "__main__":
    {"install": install, "revert": revert}[sys.argv[1]]()
