# Changelog

All notable changes to the Orbital theme. The theme is still **pre-release**; v0.1.0 is the first tag, and the entries describe the current state rather than a sequence of versions.

## Unreleased

Nothing yet.

## v0.1.0 — 2026-09-26

First tagged version (pre-release): everything below.

### Dock, keyboard and clock

- Dock tooltips show just the app name (no "right-click for options").
- A window on a special workspace (the scratchpad terminal) is not listed in the dock while that workspace is hidden;
  it appears while it is up, and pinning it keeps it always.
- The layout menu shows the language with a 2-3 letter country on the left (`Portuguese (BR)`) and the variant on the right
  (`ABNT2`); every layout has a variant label (defaults: `ABNT2` for br, `QWERTY` for us, `Standard` otherwise)
- The time in the bar is 2px larger.

### Languages

- The interface is available in English and Brazilian Portuguese (system locale, or `ORBITAL_LANG=pt|en`); day and month
  names in the calendar follow it. `scripts/test-i18n.sh` keeps the dictionary and the plugins in sync.

### Installer: adopts what you already have

- The installer no longer adds a second copy of something your Hyprland config already does: glass rules, the launcher
  key, gaps and the touchpad gesture are left alone (dotfiles symlinks are followed and never replaced), and an
  `orbital-keyboard.lua` you wrote yourself is kept. `--keep-bar` keeps the bar you use now.
- `--refresh-theme` overwrites the theme copy (after a backup); `--theme-dir DIR` (or the prompt, in a terminal) keeps it
  elsewhere and links `themes/orbital` to it.
- Run from a clone in any folder, the installer copies the theme files that are missing into
  `~/.config/omarchy/themes/orbital` (never overwriting the ones already there).
- `--full` enables the 4-finger horizontal touchpad swipe for workspaces (`--no-gestures` skips it).
- `--uninstall` removes the `require` lines before the files (no transient Hyprland config error), and never removes
  symlinks or files that are not the installer's own.
- Tested on a sandbox that imitates a dotfiles setup, and on a clean VM (fresh install from the public URL, all screens,
  idempotent re-install, uninstall).

### Installer: all or nothing

- `install.sh` applies nothing until everything succeeds. Phase one checks the package is complete, that **every**
  `manifest.json` is accepted by the real `omarchy plugin validate`, that `shell.json` is valid JSON, that the
  destinations are writable and that the shell answers — writing nothing, and reporting *all* the problems it found at
  once. Phase two applies the changes behind a snapshot with an undo stack. Phase three reads the real state back (every
  plugin enabled, the bar in use, the widgets in place and in order, no `require` without a file) and only then restarts
  the shell. Any failure aborts, restores the previous state — with the shell stopped, or it rewrites `shell.json` from
  memory — and prints what failed and what to do next.
- Widget placement and ordering are checked against `shell.json` with retries instead of trusting the CLI's exit code:
  `omarchy plugin enable --section` and `omarchy bar move` report `omarchy-shell is not responding` under a burst of
  calls and sometimes apply the change anyway.
- A shell that is still starting up is given time to answer before the install is called off.
- The documented path (`--bar-widgets`) selects Orbital's floating bar and enables the divider; it appends the dock
  (left), the workspaces (center) and the keyboard flag, hairline divider and clock (right), and leaves the bar's
  position alone.
- `--full` reproduces the author's whole desktop (bar at the bottom, widget layout, Super+S launcher, gaps, text size 10,
  Alt+Shift layout switching, dock pins) after backing up `shell.json`.
- Steps that would only degrade something — a missing optional command such as `curl` for the weather, a notification bell
  that could not be fetched — are reported as warnings and never block the install.
- `--dry-run` still writes nothing, `--no-restart` leaves the shell alone, `--uninstall` removes everything the installer
  added, and `--no-launcher-key` / `--no-alt-shift` / `--fix-terminal-shortcuts` / `--keyboard-layouts` opt out of the
  individual extras.

### Bar and widgets

- `orbital.floating-bar`: self-contained floating bar (rounded corners, a gap off the edge), the default bar.
  `orbital.bar` is kept and documented as the alternative; only the bar named in `shell.json`'s `.bar.id` is ever loaded.
- `orbital.dock` (derived from arc.dock, MIT), `orbital.workspaces`, `orbital.keyboard` (country flags, layout dropdown),
  `orbital.divider` (hairline) and `orbital.clock` (clock and calendar).
- `orbital.worldclock`, `orbital.account` (avatar with an Omarchy icon fallback and an `orbital-avatar` helper),
  `orbital.appearance` (color picker: 18 colors — accent plus glass tint — custom hex, borders following the accent,
  wallpaper untouched), `orbital.launcher` (Recommended, per-app context menu, move-to-category, themed uninstall
  confirmation) and `orbital.crash` with the shared `orbital.ui` contract (themed crash modal).
- Theme-level font base size 10 and configurable text size; Alt+Shift layout switching that works in either order; a
  keybind audit that frees Ctrl+Enter in Ghostty.
- `CREDITS.md` itemizes the provenance of the six wallpapers; `docs/NOTICE.md` covers attribution and the limits of a
  pre-release.

### Tests

- `scripts/test-install.sh`: sandbox with a realistic `omarchy` stub and seven forced-failure scenarios
  (`ORBITAL_FAIL_AT`) proving a failed install leaves nothing behind — no plugin folders, byte-identical `shell.json`,
  no `orbital.lua`, no hook, no systemd drop-in, no accent baseline, no dock pins — plus the failure report naming the
  problem, plus `--dry-run`.
- `scripts/e2e-fresh-install.sh`: installs the theme from the public GitHub URL in a clean account, then forces a
  re-install to fail and requires the real system to be left exactly as it was.
- `scripts/e2e-testbed.sh` and `scripts/e2e-screens.sh`: end-to-end checks of the `--full` path and screenshots in the
  test VM; `scripts/keybind-audit.sh` checks the keybinds.

### Docs

- README: per-plugin options, attribution and how each one is installed; both bars documented; the files Omarchy itself
  drops from a git-installed theme (Lua, terminal configs, `vscode.json`); a "Check it worked" section; update
  instructions; how to check the install; an all-or-nothing section with a table of the failures it can report; and which
  stock widgets Orbital takes over (Omarchy allows a single workspaces and a single clock widget) with the commands to
  hand a role back.
- README and NOTICE point at the real GitHub URL and carry no local paths; every manifest declares its license and
  author; MIT license.
