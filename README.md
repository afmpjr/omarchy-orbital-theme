# Orbital

A dark, glassy Omarchy theme inspired by Earth seen from orbit: floating taskbar and dock, a centered app drawer, calendar,
world clock, a themed crash dialog, and a **color picker that recolors the accent *and* the glass tint** (18 colors, including
white, gray and black, or any hex).

> Status: **pre-release.** Developed and measured on one machine (Omarchy 4.x, 1366x768 @2x). See *Known limits*.

## What is in the box

| Part | What it does | Installed by |
|------|--------------|--------------|
| Theme (repo root) | `colors.toml`, `shell.toml` (menu / popups / notifications glass tokens), terminals, GTK, btop, ... | `omarchy theme install` |
| `plugins/orbital.launcher` | App drawer: search, categories, Recommended, per-app context menu (pin, move to category, uninstall) | `install.sh` |
| `plugins/orbital.dock` | Dock (bar widget): pinned + running apps, context menu | `install.sh --bar-widgets` |
| `plugins/orbital.clock`, `orbital.workspaces`, `orbital.divider` | Calendar popup with real reminders and weather, numbered workspace chips, hairline divider (bar widgets) | `install.sh --bar-widgets` |
| `plugins/orbital.account` | Profile card, links, power actions | `install.sh` |
| `plugins/orbital.appearance` | Color picker window (+ `orbital-accent.py`) | `install.sh` |
| `plugins/orbital.worldclock` | World clock, alarms, timer | `install.sh` |
| `plugins/orbital.crash` | "Process crashed" toast -> themed modal -> *Diagnose with AI* | `install.sh` |
| `plugins/orbital.ui` | Shared UI contract (tokens + dialog); library, not a plugin | `install.sh` |
| `hypr/orbital.lua` | Blur for the popups, rounded windows, glass terminals, eased horizontal workspace slide | `install.sh` |

Why two steps? `omarchy theme install` only stages theme files (and drops `*.lua`, terminal configs and `vscode.json` from git
themes), and plugins are added with `omarchy plugin add`, one repository each. `install.sh` bridges the gap.

## Install

```bash
omarchy theme install https://github.com/<you>/omarchy-orbital-theme   # theme name becomes "orbital"
cd ~/.config/omarchy/themes/orbital
./install.sh --bar-widgets        # plugins, Hyprland part, crash drop-in, baseline for the color picker
omarchy theme set Orbital
```

`install.sh` never edits `shell.json` by hand (it uses `omarchy plugin enable`), backs up what it replaces outside the plugins
folder, and is idempotent. `--dry-run` shows what it would do; `--uninstall` removes everything it added.
Without `--bar-widgets` your bar layout is left alone.

## Color picker

Open the account menu (avatar in the dock) -> **Appearance**. Every color rotates all blue-ish tones of the pristine theme
(accent, navy glass, blue-grey text) to the chosen hue; white/gray/black drop saturation. The wallpaper is never touched.
It regenerates the theme from a pristine copy in `~/.local/state/omarchy/orbital-accent-base/`, so choices never compound.
CLI: `python3 ~/.config/omarchy/plugins/orbital.appearance/orbital-accent.py <preset|#rrggbb|list|current>`.

## Requirements

Omarchy with the Quickshell-based shell (plugins), Hyprland with Lua config, `python3`, `jq`. Weather uses `wttr.in`; the
crash dialog uses `systemd-coredump`. The bar is whichever you use; the dock/clock/workspaces are ordinary bar widgets.

## Known limits

- Layout was tuned at 1366x768 @2x with the system monospace font; other scales are untested.
- Wallpapers: only a plain gradient is bundled until artwork provenance is settled (see `docs/NOTICE.md`).
- `hypr/orbital.lua` is loaded last from `~/.config/hypr/hyprland.lua`; if you set the same options later they win.
- The QML cache of `omarchy-shell` means new/edited plugins need `omarchy restart shell`.

## Development

`scripts/test-install.sh` runs the installer and the color picker in a throwaway `$HOME` with a stubbed `omarchy`.
