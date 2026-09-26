# Orbital

A dark, glassy Omarchy theme inspired by Earth seen from orbit: floating taskbar and dock, a centered app drawer, calendar,
world clock, a themed crash dialog, and a **color picker that recolors the accent *and* the glass tint** (18 colors, including
white, gray and black, or any hex).

> Status: **pre-release.** Developed and measured on one machine (Omarchy 4.x, 1366x768 at scale 1). See *Known limits*.

## What is in the box

| Part | What it does | Installed by |
|------|--------------|--------------|
| Theme (repo root) | `colors.toml`, `shell.toml` (menu / popups / notifications glass tokens), terminals, GTK, btop, ... | `omarchy theme install` |
| [`orbital.launcher`](plugins/orbital.launcher/) | App drawer: search, categories, Recommended, per-app context menu (pin, move to category, uninstall) | `install.sh` |
| [`orbital.dock`](plugins/orbital.dock/) | Dock (bar widget): pinned + running apps, context menu | `install.sh --bar-widgets` |
| [`orbital.clock`](plugins/orbital.clock/), [`orbital.workspaces`](plugins/orbital.workspaces/), [`orbital.divider`](plugins/orbital.divider/) | Calendar popup with real reminders and weather, numbered workspace chips, hairline divider (bar widgets) | `install.sh --bar-widgets` |
| [`orbital.account`](plugins/orbital.account/) | Profile card, links, power actions | `install.sh` |
| [`orbital.appearance`](plugins/orbital.appearance/) | Color picker window (+ `orbital-accent.py`) | `install.sh` |
| [`orbital.worldclock`](plugins/orbital.worldclock/) | World clock, alarms, timer | `install.sh` |
| [`orbital.crash`](plugins/orbital.crash/) | "Process crashed" toast -> themed modal -> *Diagnose with AI* | `install.sh` |
| [`orbital.keyboard`](plugins/orbital.keyboard/) | Tray widget: flag of the active layout (only with 2+ layouts); click for a dropdown to switch. Alt+Shift also cycles, with `--full` | `install.sh --bar-widgets` |
| [`orbital.floating-bar`](plugins/orbital.floating-bar/) | The bar: Omarchy's bar floating off the edge, rounded corners. Fork of `charlieras262/floating-bar` | `install.sh` (default bar) |
| [`orbital.bar`](plugins/orbital.bar/) | Alternative bar with dock, workspace pills and system controls built in | `install.sh` (pick with `omarchy plugin enable orbital.bar`) |
| [`orbital.ui`](plugins/orbital.ui/) | Shared UI contract (tokens + dialog); library, not a plugin | `install.sh` |
| `hypr/orbital.lua` | Blur for the popups, rounded windows, glass terminals, eased horizontal workspace slide | `install.sh` |

Each plugin has its own README with options and attribution. Two bars ship on purpose: only the one named in
`shell.json`'s `.bar.id` is ever loaded, so the other is just an option in the bar menu.

**Languages.** English and Brazilian Portuguese. The interface follows the system locale (`pt*` gives Portuguese, anything else
English); set `ORBITAL_LANG=pt` or `en` in the shell's environment to force one. The crash dialog follows the same rule. Strings
live in [`plugins/orbital.ui/I18n.js`](plugins/orbital.ui/I18n.js); `scripts/test-i18n.sh` fails if one is missing or unused.

**Cloned somewhere else?** `install.sh` works from any folder: it copies the theme files that are not yet in
`~/.config/omarchy/themes/orbital` (terminal configs, Lua and wallpaper included) and never overwrites one that is already
there, since the accent picker rewrites them. Then `omarchy theme set orbital`.

Why two steps? `omarchy theme install` only stages theme files (and drops `*.lua`, terminal configs and `vscode.json` from git
themes), and plugins are added with `omarchy plugin add`, one repository each. `install.sh` bridges the gap.

## Install

```bash
omarchy theme install https://github.com/afmpjr/omarchy-orbital-theme   # the theme lands as "orbital"
cd ~/.config/omarchy/themes/orbital
./install.sh --bar-widgets        # plugins + widgets, Hyprland part, crash dialog, color-picker baseline
omarchy theme set orbital
```

**All or nothing.** The theme is applied only if the whole install works. Before touching anything the installer checks
everything it can check (package complete, every manifest accepted by your Omarchy, `shell.json` valid, every directory
writable, shell answering) and lists *all* the problems it found; then it applies the changes with a snapshot of
everything it replaces, and finally reads the real state back — every plugin enabled, the bar in use, the widgets in
place, no `require` without a file. If any of that fails, the install **aborts, rolls back to the state you had before,
and tells you what failed**; your shell is only restarted when everything is in place. A step that would only degrade
something (a missing `curl` for the weather, a notification bell that could not be fetched) is reported as a warning
instead, and never blocks the install.

`--bar-widgets` is the flag that puts the widgets in your bar. It **appends** Orbital's to the sections your bar already
uses — the dock on the left, the workspaces in the middle, the keyboard flag, the hairline divider and the clock/calendar
on the right — and switches the bar itself to Orbital's floating one (rounded corners, a gap off the edge). It does
**not** move your bar or change its position.

One thing to know: Omarchy allows a single workspaces widget and a single clock, so Orbital's two **take the place of**
`omarchy.workspaces` and `omarchy.clock` — that is Omarchy switching roles over, not the installer deleting anything. Every
other stock widget (menu, indicators, tray, weather, system-update, network, audio, bluetooth, power, agents, monitor,
keyboard layout) stays exactly where it was. To hand a role back to the stock widget, enable it again and Orbital's steps
aside:

```bash
omarchy plugin enable omarchy.workspaces --section left    # back to the stock workspaces
omarchy plugin enable omarchy.clock --section center        # back to the stock clock
```

`./install.sh --full` reproduces the author's whole desktop instead (bar at the bottom, widget layout, **Super**+**S**
launcher, gaps, text size 10, Alt+Shift layout switching, dock pins); it backs up `shell.json` first.

`install.sh` never edits `shell.json` by hand (it uses `omarchy plugin enable`), backs up what it replaces outside the plugins
folder, and is idempotent. `--dry-run` shows what it would do; `--uninstall` removes everything it added.
Without `--bar-widgets` your bar layout is left alone.

## Check it worked

```bash
omarchy plugin list | grep orbital   # 12 enabled; the bar you are NOT using shows "disabled"
hyprctl configerrors                 # must print nothing: one stray line breaks the whole Hyprland config
hyprctl layers | grep omarchy-bar    # the bar, floating with a gap off the edge of the screen
jq -r '[.bar.layout.left[].id, .bar.layout.right[].id] | join(" ")' ~/.config/omarchy/shell.json
```

On screen: the dock on the left of the bar, and on the right the keyboard flag, the hairline divider and the clock
(click it for calendar, reminders and weather). The avatar in the dock opens the account card, and **Appearance** there
is the color picker. The app drawer (launcher) and Alt+Shift layout switching are bound **only by `--full`**; in this
path you can always open the drawer with `omarchy-shell shell toggle orbital.launcher`. If a widget is missing after
installing or editing a plugin, run `omarchy restart shell` — the QML cache only reloads on restart.

## Update

```bash
omarchy theme update                                    # re-pulls every user-installed git theme
cd ~/.config/omarchy/themes/orbital && ./install.sh --bar-widgets
```

`install.sh` is idempotent: it re-applies what is missing and leaves what you changed alone. Add `--full` if you use it,
or `--uninstall` first for a clean slate.

## If the install fails

Nothing is applied and the installer exits non-zero. The report names every problem it found, and everything it had
already changed is put back (plugin folders, `shell.json`, the Hyprland files, the crash drop-in, the dock pins) — so
fixing the cause and running the same command again is always safe. Failures worth knowing about:

| Message | What it means |
|---------|---------------|
| `Cannot install yet. Nothing was changed.` | A pre-flight check failed: nothing was even started. The list under it is everything wrong at once. |
| `the Omarchy shell is not answering` | `omarchy plugin list` fails, so no plugin could be enabled. Start the shell and retry. |
| `this Omarchy rejects the manifest of <id>` | Your Omarchy version does not accept that plugin's `manifest.json`. |
| `could not place <widget> in the <section> section of the bar` | The shell stopped answering mid-install. The installer retries and checks the layout itself, so this means it really did not land. |
| `the right side of the bar is out of order` | The widgets are there but not in the order the divider was designed for (keyboard, hairline, clock). |
| `... is installed but not enabled after the install` | The verification pass: Omarchy did not keep the change. This is what stops a half-installed theme. |
| `both bars are enabled at once` | Only the bar in `shell.json`'s `.bar.id` is ever loaded. The installer disables the other one; if it still shows up here, something else re-enabled it. |

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
fullscreen. `--full` also enables the **4-finger horizontal touchpad swipe** to switch workspaces (`--no-gestures` skips it; it is left alone if your config already sets a gesture). The two bindings `--full` adds are opt-out: `--no-launcher-key` (SUPER+S opens the launcher and replaces Omarchy's own
SUPER+S) and `--no-alt-shift` (Alt+Shift layout switching; it also fires after editor chords such as Alt+Shift+Down).
**Installer options, in one place**

| Option | What it does |
|---|---|
| `--full` | The author's whole desktop: bar layout, launcher key, gaps, text size 10, keyboard layouts + Alt+Shift, 4-finger swipe, dock pins |
| `--bar-widgets` | Only place the Orbital widgets in your current bar |
| `--keyboard-layouts us,br` | Layouts for the keyboard widget (default: the ones in your `input.lua`) |
| `--keep-bar` | Keep the bar you use now instead of switching to `orbital.floating-bar` |
| `--no-launcher-key`, `--no-alt-shift`, `--no-gestures` | Skip that one binding |
| `--fix-terminal-shortcuts` | Free Ctrl+Enter in Ghostty (also part of `--full`) |
| `--refresh-theme` | Overwrite the theme copy in `themes/orbital` (old copy saved first; the accent goes back to blue) |
| `--theme-dir DIR` | Keep the theme copy in DIR and link `themes/orbital` to it (asked for in a terminal, default kept) |
| `--dry-run`, `--no-restart`, `--uninstall` | Preview, skip the shell restart, or remove what was installed |

**Already have a setup?** The installer adopts what it finds instead of adding a second copy: glass rules, a launcher key, gaps or a
gesture already in your Hyprland config (dotfiles symlinks are followed, and never replaced) are left alone, and an
`orbital-keyboard.lua` you wrote yourself is kept. `--keep-bar` keeps the bar you use now instead of switching to
`orbital.floating-bar`. Preview everything first with `./install.sh --full --dry-run`.
Without `--full` Orbital binds nothing at all, so your own keys are left as they are.

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

Omarchy with the Quickshell-based shell (plugins), Hyprland with Lua config, `python3`, `jq`. The bar is whichever you
use; the dock/clock/workspaces are ordinary bar widgets.

Beyond those, a few commands are called at runtime by individual widgets. `install.sh` checks for them and tells you
which one is missing instead of leaving you with a blank widget:

| Command | Used by | If missing |
|---------|---------|-----------|
| `hyprctl` | floating-bar gaps, keyboard device list | bar gaps fall back to the default, keyboard layout widget is empty |
| `xkbcli` | keyboard widget, exotic layouts | only the standard layouts are offered |
| `curl` | weather in the clock | the weather line stays empty |
| `timedatectl` | world clock | the timezone list is empty |
| `omarchy-reminder` | reminder indicator | indicator hidden |
| `omarchy-update-available` | system update indicator | indicator hidden |
| `omarchy-voxtype-status` | dictation indicator | indicator hidden |

The crash dialog needs `systemd-coredump`; weather needs network access to `wttr.in`.

Tested on Omarchy 4.x. The plugins are read from `~/.config/omarchy/plugins/` and the theme from
`~/.config/omarchy/themes/orbital/`, so nothing is written outside those, `~/.config/hypr/`, `~/.config/systemd/user/` and
`~/.local/state/omarchy/`.

If a `require("hypr.orbital-*")` line in `~/.config/hypr/hyprland.lua` has no matching `.lua` file, Hyprland refuses to
load the config at all. `install.sh` drops such a dangling line (and says so) instead of leaving it there.

## Known limits

- Layout was tuned at 1366x768 at scale 1 with the system monospace font; other scales are untested.
- `hypr/orbital.lua` is loaded last from `~/.config/hypr/hyprland.lua`; if you set the same options later they win.
- The QML cache of `omarchy-shell` means new/edited plugins need `omarchy restart shell`.
- Omarchy itself refuses terminal/Lua/VS Code files that arrive with a theme installed from a git repo. `kitty.toml`,
  `alacritty.toml`, `foot.ini`, `ghostty.conf`, `neovim.lua` and `vscode.json` in this repo are therefore **reference
  copies**: they document the intended look, and the installer applies what it can through `omarchy config`, but they do
  not reach your dotfiles. Hyprland's `hypr/orbital.lua` is not affected — `install.sh` writes it directly.
- A plugin whose QML `import` cannot be resolved (an Omarchy or Quickshell build without that module) does not load;
  the rest of the shell is unaffected. `scripts/test-install.sh` checks every manifest with `omarchy plugin validate`
  (the schema is Omarchy's, not the theme's) and `scripts/e2e-testbed.sh` repeats it on a clean Omarchy VM.

## License

MIT (see `LICENSE`), including the bundled wallpapers. Per-file image provenance: [`CREDITS.md`](CREDITS.md) — **its source
column still needs the author's confirmation**. Third-party notices in [`docs/NOTICE.md`](docs/NOTICE.md).

## Development

`scripts/test-install.sh` runs the installer and the color picker in a throwaway `$HOME` with a stubbed `omarchy`.
`scripts/e2e-fresh-install.sh` is the honest test: it resets a clean Omarchy VM and follows the four
commands above from the public URL, then checks the theme, the 13 plugin folders, the enabled plugins, the bar in use,
the Hyprland hook and `hyprctl configerrors`. It needs a VM you can wipe (`TESTBED=/path/to/omarchy-testbed`).

