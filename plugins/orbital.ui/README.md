# orbital.ui — shared UI contract for Orbital plugins

Not a plugin (no `manifest.json`, so the shell's scanner ignores it). Plugins import it by relative path:

```qml
import "../orbital.ui" as OrbitalUi   // then OrbitalUi.OrbitalDialog {}
```

- `OrbitalTokens.qml` — design tokens derived from the active theme (`Color.menu.*`, `Color.accent`, `Style.*`) and the
  three tones `neutral | primary | danger`. Ask `tk.tone(name, hovered)` for `{ text, fill, border }`.
- `OrbitalDialog.qml` — modal dialog. Callers describe content (`title`, `glyph`, `tone`, `message`, `rows`, `buttons`)
  and react to `activated(id)` / `dismissed()`; they never style anything. Full property list in the file header.

Rules: no hardcoded palette outside `OrbitalTokens` tones; no colors or radii in consumers; the dialog never closes
itself or runs commands.

Note: the shell caches QML by file URL for the whole session (`Qt.clearComponentCache` is not available), so an edited
file only takes effect after an `omarchy-shell` restart, or under a new file name.

Consumers: `orbital.crash` (modal). The crash toast that opens it is themed by the `[notifications]` section of the active
theme's `shell.toml` (same glass card as `[menu]`/`[popups]`), not by this library.
