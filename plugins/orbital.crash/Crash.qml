// Orbital Crash — overlay entry for the crash modal.
//
// Maps the orbital-crash-watch payload onto the orbital.ui dialog contract and
// reacts to its signals. No styling here: colors, radii, type and buttons come
// from orbital.ui (OrbitalDialog / OrbitalTokens).
//
//   { "pid": "873", "comm": "wireplumber", "exe": "/usr/bin/wireplumber",
//     "signal": "SIGSEGV", "title": "Process crashed", "dismiss": "Dismiss",
//     "diagnose": "Diagnose with AI",
//     "rows": [ {"label": "PID", "value": "873", "crash": true?}, ... ] }
//
// "Diagnose with AI" runs the stock omarchy-agent-crash with the same argv the
// original toast used, so the diagnose-crash skill flow is unchanged. Dismiss
// is focused by default so a stray Enter never launches an agent.

import Quickshell
import QtQuick
import "../orbital.ui" as OrbitalUi

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string pid: ""
  property string comm: ""
  property string exe: ""
  property string signalName: ""
  property string titleText: "Process crashed"
  property string dismissText: "Dismiss"
  property string diagnoseText: "Diagnose with AI"
  property var rows: []

  // nf-md-robot_dead, same glyph the stock crash toast uses.
  readonly property string crashGlyph: "󱚡"

  function open(payloadJson) {
    var p = ({})
    try { p = JSON.parse(payloadJson || "{}") } catch (e) { p = ({}) }

    root.pid = String(p.pid || "")
    root.comm = String(p.comm || "")
    root.exe = String(p.exe || "")
    root.signalName = String(p.signal || "")
    if (p.title) root.titleText = String(p.title)
    if (p.dismiss) root.dismissText = String(p.dismiss)
    if (p.diagnose) root.diagnoseText = String(p.diagnose)

    var rows = []
    var src = Array.isArray(p.rows) ? p.rows : []
    for (var i = 0; i < src.length; i++)
      rows.push({ label: src[i].label, value: src[i].value, tone: src[i].crash ? "danger" : "neutral" })
    root.rows = rows

    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "orbital.crash")
  }

  function toggle(payloadJson) {
    if (root.opened) root.dismiss()
    else root.open(payloadJson)
  }

  // Lets the watcher confirm the modal is really on screen (shell IPC
  // `call orbital.crash status`) and fall back to the stock toast if not.
  function status(arg) {
    return root.opened ? "open" : "closed"
  }

  function diagnose() {
    var args = [root.omarchyPath + "/bin/omarchy-agent-crash", root.pid, root.comm, root.exe, root.signalName]
    root.dismiss()
    Quickshell.execDetached(args)
  }

  OrbitalUi.OrbitalDialog {
    opened: root.opened
    layerNamespace: "orbital-crash"
    tone: "danger"
    glyph: root.crashGlyph
    title: root.titleText + ": " + root.comm
    rows: root.rows
    defaultButton: 0
    buttons: [
      { id: "dismiss", label: root.dismissText, role: "neutral" },
      { id: "diagnose", label: root.diagnoseText, role: "primary" }
    ]
    onActivated: function(id) { if (id === "diagnose") root.diagnose(); else root.dismiss() }
    onDismissed: root.dismiss()
  }
}
