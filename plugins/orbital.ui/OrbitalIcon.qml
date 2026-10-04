// A themed icon, tinted with the current accent.
//
// Why this exists: the symbolic SVGs under /usr/share/icons ship a hardcoded
// fill (#2e3436, Adwaita's dark grey). Hand one to a plain QML Image and you get
// a near-black glyph on a dark panel — technically rendered, visually wrong. The
// AdwaitaLegacy PNGs this replaced were coloured, which is why the panel looked
// inconsistent before: right shapes, wrong palette, in both directions.
//
// The recolour is a MultiEffect colorization pass over the icon's luminance, so it
// works for any monochrome asset and needs no per-icon colour table. sourceRole
// is what Qt6's own ColorOverlay uses: QtQuick.Effects does not re-export the
// internal role, so a hidden Image inside the effect feeds it instead of taking
// the effect as the image's own layer, which would recurse.
//
// Usage:
//   import "../orbital.ui" as OrbitalUi
//   OrbitalUi.OrbitalIcon { name: "system-shutdown-symbolic"; size: 18 }

import Quickshell
import QtQuick
import QtQuick.Effects
import qs.Commons

// tint defaults to the shell's accent, so every themed icon in the theme follows
// the colour the user picked. Pass an explicit color only where an icon should
// stay neutral.
Item {
  id: root

  property string name: ""
  // An absolute path or file:// URL. Takes precedence over name, for callers that
  // already resolved a file (app icons from the desktop database, for instance).
  property string source: ""
  property int size: 18
  property color tint: Color.accent
  // Keep the asset's own colours. For the AdwaitaLegacy raster set, which is
  // already coloured; the symbolic set is not.
  property bool preserveColors: false

  implicitWidth: size
  implicitHeight: size

  // Prefer a real path from the icon index over the themed name, and fall back to
  // the colored legacy raster only if no SVG exists for the name at all.
  // (Was OrbitalIcons.pick(name, preserveColors): pick() never existed on the
  // singleton, so instantiating this component threw. file() is the real API.)
  readonly property string _resolved: OrbitalIcons.file(name)

  Image {
    id: base
    anchors.fill: parent
    source: root.source.length > 0 ? root.source : root._resolved
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    cache: true
    sourceSize.width: root.size * 2
    sourceSize.height: root.size * 2
    visible: false
  }

  MultiEffect {
    anchors.fill: parent
    source: base
    enabled: !root.preserveColors
    colorization: 1
    colorizationColor: root.tint
  }
}
