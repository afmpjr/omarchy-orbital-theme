# Orbital

A dark, glassy Omarchy theme inspired by Earth seen from orbit: floating taskbar and dock, a centered app drawer, calendar,
world clock, a themed crash dialog, and a **color picker that recolors the accent *and* the glass tint** (18 colors, including
white, gray and black, or any hex).

> Status: **pre-release.** Developed and measured on one machine (Omarchy 4.x, 1366x768 at scale 1). See *Known limits*.

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
| `plugins/orbital.keyboard` | Tray widget: country flag of the active keyboard layout; click for a dropdown to switch. Alt+Shift also cycles | `install.sh --bar-widgets` |
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

## Keyboard layouts

The `orbital.keyboard` tray widget shows the flag of the active layout (text label for layouts without a flag) and opens a
dropdown on click. It only appears when there are two or more layouts. `install.sh --full` reads your layouts from
`~/.config/hypr/input.lua` (or use `--keyboard-layouts br,us`) and makes **Alt+Shift** switch, in either order, through a small
`~/.config/hypr/orbital-keyboard.lua` you can edit or delete. (xkb's own `grp:alt_shift_toggle` only fires when Alt goes down
while Shift is already held, so it is removed from `kb_options` and two Hyprland release binds are used instead.) Selecting from the dropdown switches every
keyboard on the seat (needed when keyd/fcitx5 sit between the keys and Hyprland).

## Shortcut conflicts

`scripts/keybind-audit.sh` (read-only, works on any Omarchy desktop) reports: the same chord bound twice in Hyprland; global
binds without Super that steal chords from every app; Ghostty built-ins that shadow keys TUIs expect (Ctrl+Enter is
fullscreen, Ctrl+Shift+Enter zooms a split, Ctrl+Tab switches tabs); and Orbital's own additions. `install.sh --full` frees
**Ctrl+Enter** in Ghostty (`--fix-terminal-shortcuts` does only that), because it made Claude Code and other TUIs jump to
fullscreen. Orbital's other bindings are opt-out: `--no-launcher-key` (SUPER+S opens the launcher and replaces Omarchy's own
SUPER+S) and `--no-alt-shift` (Alt+Shift layout switching; it also fires after editor chords such as Alt+Shift+Down).

## Avatar

The dock and the account card show `~/.config/omarchy/avatar.png` (the same file the lock-screen plugins read). Without it they
show the Omarchy icon. To set yours:

```bash
~/.config/omarchy/plugins/orbital.account/orbital-avatar ~/Pictures/me.jpg   # any image, cropped to a square
~/.config/omarchy/plugins/orbital.account/orbital-avatar --github            # your GitHub picture (needs `gh auth login`)
~/.config/omarchy/plugins/orbital.account/orbital-avatar --reset             # back to the Omarchy icon
```

Name and e-mail on the card come from `omarchy-refresh-identity` (GitHub) or `git config --global user.name/email`.

## Requirements

Omarchy with the Quickshell-based shell (plugins), Hyprland with Lua config, `python3`, `jq`. Weather uses `wttr.in`; the
crash dialog uses `systemd-coredump`. The bar is whichever you use; the dock/clock/workspaces are ordinary bar widgets.

## Known limits

- Layout was tuned at 1366x768 at scale 1 with the system monospace font; other scales are untested.
- `hypr/orbital.lua` is loaded last from `~/.config/hypr/hyprland.lua`; if you set the same options later they win.
- The QML cache of `omarchy-shell` means new/edited plugins need `omarchy restart shell`.

## License

MIT, including the bundled wallpapers (generated by the author). Third-party notices in `docs/NOTICE.md`.

## Development

`scripts/test-install.sh` runs the installer and the color picker in a throwaway `$HOME` with a stubbed `omarchy`.
