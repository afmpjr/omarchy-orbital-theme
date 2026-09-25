# orbital.appearance — accent and glass color picker

Window that recolors the theme: 18 presets (accent **and** glass tint, including white, gray and black) or any custom hex.
The border color follows the accent. The wallpaper is never touched.

- **Kind:** `overlay` · **Entry point:** `Appearance.qml` · **Version:** 1.0.0
- **Installed by:** `install.sh` (always, as an overlay)

## How it works

`orbital-accent.py` regenerates the theme folder in place from a pristine baseline:

| Path | Role |
|------|------|
| `~/.local/state/omarchy/orbital-accent-base` | Pristine (blue) copy of the theme, created by `install.sh` |
| `~/.local/state/omarchy/orbital-accent.json` | Current accent / glass state |
| `~/.config/omarchy/themes/orbital` | Regenerated output — **edit the baseline, not the theme** |

Because the theme folder is generated, any manual change to `~/.config/omarchy/themes/orbital` is lost the next time a color
is picked. Change `orbital-accent-base` instead, then re-apply.

## Requirements

`python3` (checked by `install.sh`). A missing baseline is a hard error, not a silent no-op.

## After changing colors

```bash
omarchy theme set Orbital     # re-reads shell.toml
omarchy restart shell         # omarchy-shell caches QML and directory listings for the session
```

## License

MIT (see the repository `LICENSE`).
