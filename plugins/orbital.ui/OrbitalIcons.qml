pragma Singleton
// Orbital icon resolution.
//
// Quickshell.iconPath(name, true) resolves nothing on a stock Omarchy install:
// instrumented on the testbed it returned "" for every name tried, including
// image-missing-symbolic and a name that cannot exist, so any Image sourced from
// it draws nothing and the gap is silent — no log line, no error. The icons the
// first-party plugins ship resolve because those plugins scan the XDG icon
// directories themselves and hand QML a file:// URL (see AppLibrary.iconSource()
// and orbital.launcher / orbital.dock, which each carry their own copy of that
// scan).
//
// This is that scan, once, for every plugin that needs a themed system icon.
// Three deliberate differences from the launcher/dock copies:
//
//   - it indexes the whole tree, not only */apps/* and */devices/*. The panel
//     icons live in symbolic/actions, symbolic/status and symbolic/legacy,
//     which the narrower scan never matched.
//   - the theme's own icon set (plugins/orbital.ui/icons/, shipped with the
//     repo) is scanned first AND outscores everything, so an Orbital glyph
//     always wins over the same freedesktop name in Adwaita/AdwaitaLegacy.
//     The system sets stay as fallback for names the theme does not ship.
//
// Usage:
//   import "../orbital.ui" as OrbitalUi
//   Image { source: OrbitalUi.OrbitalIcons.file("system-reboot-symbolic") }
//
// or for a plugin that only needs a name it chose itself:
//
//   var resolved = OrbitalUi.OrbitalIcons.file(name)

import Quickshell
import Quickshell.Io
import QtQuick
// Util.fileUrl comes from the shell's own Commons module, not from Quickshell.
import qs.Commons

// Item rather than QtObject only so the index-scan Process can be a child: a
// QtObject has no default property to attach it to. Nothing is ever rendered.
Item {
  id: icons

  // name -> { path, score }, best candidate only. Swapping the object re-evaluates
  // every binding that reads it, which is what makes the icons appear once the
  // scan lands.
  property var index: ({})

  readonly property bool ready: Object.keys(index).length > 0

  // Directories in resolution order. The theme's own icon set first (shipped
  // with the repo, installed under the plugin dir), then the active theme,
  // then the XDG data dirs, then the legacy set that still holds names the
  // current themes dropped.
  readonly property var searchDirs: {
    var dirs = []
    dirs.push(Quickshell.env("HOME") + "/.config/omarchy/plugins/orbital.ui/icons")
    var theme = Quickshell.env("QT_QPA_PLATFORMTHEME") || ""
    dirs.push(Quickshell.env("HOME") + "/.icons")
    dirs.push(Quickshell.env("HOME") + "/.local/share/icons")
    dirs.push("/usr/local/share/icons")
    dirs.push("/usr/share/icons")
    if (theme.length > 0) dirs.push("/usr/share/icons/" + theme)
    // AdwaitaLegacy keeps the 16x16 raster names (system-shutdown,
    // preferences-desktop-theme) that Adwaita no longer ships.
    dirs.push("/usr/share/icons/AdwaitaLegacy")
    return dirs
  }

  function scanCommand() {
    var quoted = searchDirs.map(function(d) { return "'" + d + "'" }).join(" ")
    return [
      'for ext in svg png; do',
      '  for base in ' + quoted + '; do',
      '    [[ -d $base ]] && find "$base" -name "*.$ext" 2>/dev/null;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
      'done'
    ].join(' ')
  }

  // How good a candidate is for a name, higher is better. Only the best candidate
  // per name is kept, so a later directory can improve on an earlier one but never
  // make things worse.
  //
  // Ordering matters more than it looks. A plain first-hit-wins scan picks up
  // AdwaitaLegacy's raster copies (they sort before the modern set) and the panel
  // ends up with blurry, unrelated-looking glyphs instead of the symbolic icons
  // every other Omarchy surface uses. Symbolic vector wins outright, then plain
  // vector, then the largest raster. Above all of that, unconditionally: a glyph
  // from the theme's own set. The bonus (not dir order) is what guarantees the
  // win — find(1) order is never relied on for correctness.
  function score(path) {
    var s = 0
    if (path.indexOf("/orbital.ui/icons/") !== -1) return 2000
    if (/-symbolic\.svg$/i.test(path)) return 1000
    if (/\.svg$/i.test(path)) s += 500
    var m = path.match(/\/(\d+)x\d+\//)
    if (m) s += Math.min(parseInt(m[1], 10), 256)
    return s
  }

  function indexLine(path) {
    var value = String(path || "").trim()
    if (value.length === 0) return
    var file = value.slice(value.lastIndexOf("/") + 1)
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file
    if (name.length === 0) return
    var s = icons.score(value)
    var cur = icons.pending[name]
    if (cur === undefined || s > cur.score) icons.pending[name] = { path: value, score: s }
  }

  property var pending: ({})

  // The scan is started explicitly by resolve() rather than on singleton load: a
  // singleton's Component.onCompleted only fires once something first touches it,
  // and a plugin that binds a source in its own constructor can do so too early
  // for a child Process to be live. resolve() runs on the first lookup instead,
  // which is exactly when a scan is wanted.
  // Kept in a plain JS object rather than a QML property on purpose: file() runs
  // inside a binding, and writing a property that same binding reads is a binding
  // loop. A nested JS write notifies nothing.
  property var state: ({ started: false })

  function ensureStarted() {
    if (icons.state.started) return
    icons.state.started = true
    scan.running = true
  }

  Process {
    id: scan
    command: ["bash", "-c", icons.scanCommand()]
    stdout: SplitParser { onRead: function(line) { icons.indexLine(line) } }
    onStarted: icons.pending = ({})
    onExited: icons.index = icons.pending
  }

  // Lookup order: an exact name the scan found, then the other "-symbolic"
  // spelling, then a themed name Qt resolved, then image-missing. Never returns ""
  // for a caller to trip over.
  //
  // The scan is consulted before iconPath() on purpose. iconPath() resolves
  // nothing on a stock install, and where it does resolve, the icon theme's own
  // pick can be a raster copy of a name that also has a modern symbolic form.
  function file(name) {
    // Kick the scan off on the first lookup. Reading icons.index below is what
    // re-evaluates a binding that resolved to "" on that first pass.
    icons.ensureStarted()
    var value = String(name || "")
    if (value.length === 0) value = "image-missing"
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    // "-symbolic" is a suffix the theme adds to the same base name, so accept
    // either spelling rather than making every caller remember which one exists.
    var bare = value.slice(-9) === "-symbolic" ? value.slice(0, -9) : value
    for (var i = 0; i < 4; i++) {
      var tryName = [value, bare, bare + "-symbolic", value + "-symbolic"][i]
      var hit = icons.index[tryName]
      if (hit !== undefined) return Util.fileUrl(hit.path)
    }
    var themed = Quickshell.iconPath(value, true)
    if (themed && themed.length > 0) return themed
    for (var j = 0; j < 2; j++) {
      var miss = icons.index[j === 0 ? "image-missing" : "image-missing-symbolic"]
      if (miss !== undefined) return Util.fileUrl(miss.path)
    }
    return ""
  }
}
