# Changelog

All notable changes to the Orbital theme. The theme is still **pre-release**; v0.1.0 is the first tag, and the entries describe the current state rather than a sequence of versions.

## Unreleased

- New `orbital.settings` setup center (the official graphical setup; the bash TUI stays parked): sidebar with
  10 sections, live previews (accent swatches apply live, wallpaper thumbnails, data-driven bar mock),
  staged choices and one **Apply all** (single applier script, one Hyprland reload + one shell restart).
  Opens after install, from the account Appearance row (now a shortcut here) and from an apps-menu entry.
- `--uninstall` is now complete: it offers the visual theme switcher when a human is present (numbered text
  list otherwise, silent recorded-or-Tokyo-Night default for scripts), switches themes, removes the Orbital
  copy, restores `shell.json` from the pre-install backup (asking first, with a safety backup of the current
  file), and restarts the shell once. Install records the prior theme and backup path for this; suite covers
  switch, removal, restore and rollback.
- Bars start **locked** against accidental widget rearranging (the floating bar moves any widget past a 4px
  drag with no undo): the account panel has a "Lock/Unlock widgets" row backed by the `orbital-widgets-lock`
  companion script and `~/.local/state/omarchy/orbital-widgets-lock` state (missing = locked). The lock only
  gates widget rearranging — clicks and workspace chip drag-to-swap keep working, because a press that starts
  on a chip is yielded to the widget (new `claimsPress` hook) instead of grabbed by the bar. Installer creates
  the locked state, uninstall removes it, suite asserts both plus rollback.
- `orbital.workspaces` chips are draggable: drop one chip onto another to **swap the two workspaces' windows**,
  with the dragged chip's own pixels as the ghost and the accent border on the drop target (releasing elsewhere
  cancels; clicks still switch workspaces). The move sequence lives in the companion script
  `orbital-workspace-swap` (via a scratch workspace) so the drop path stays testable without a mouse.
- `orbital.bar` loads again: `Bar.qml` used `DockItem`/`DockModel` from `widgets/`, which only `widgets/qmldir`
  declares, so the bar died with "DockItem is not a type" and the shell silently fell back to `omarchy.bar`.
  `Bar.qml` now imports its own `widgets/` directory. The same failure also exposed a QML syntax error that made
  the type unresolvable in the first place: `widgets/DockItem.qml` used bare `if`/`else` blocks as `Menu` children
  for the conditional entries ("Fechar todas as janelas", "Desfixar"/"Fixar no dock") — replaced with `visible`
  bindings, same behaviour. Verified live: `bar use orbital.bar` renders with dock pins, no fallback warning.
- `orbital-accent.py` no longer crashes on the `preview-web/` tree: the installed theme deliberately excludes it
  but the pristine baseline contains it, so every picker click died with `FileNotFoundError` after writing
  `colors.toml` but before `theme refresh` — the selector silently did nothing. The tree is now skipped (like the
  installer does) and destination dirs are created defensively; the test suite asserts the apply exit code.
  The refresh also silently pushed nothing: the shell spawns the script without a login env, so `OMARCHY_PATH`
  was unset and every `shell_ipc ... || true` failed hidden (files updated, bar unchanged). The script now exports
  the same `/usr/share/omarchy` fallback the QML side uses — pink→blue round-trip verified live on the bar chip,
  no shell restart needed.
- The theme ships its own icon set (`plugins/orbital.ui/icons/`, 9 white 24×24 SVG glyphs): the account panel, its
  settings gear and chevrons, and the dock's generic-app placeholder no longer depend on Adwaita's dark symbolic
  assets, which rendered washed-out on Orbital's dark surfaces. The scanner gives the theme set absolute priority;
  system icons stay as fallback. Also fixes a latent crash: `OrbitalIcon` called `OrbitalIcons.pick()`, which never
  existed — it now uses `file()`.
- `install.sh --windows-keys` adds an opt-in set of Windows-style shortcuts (`hypr/orbital-keys-windows.lua`); never part of `--full`,
  skipped when your config already has them, removed by `--uninstall`.
- The account panel resolves themed system icons from XDG icon directories, including symbolic variants, with a visible fallback when an icon name is missing.
- `orbital.workspaces` previews each open window in its on-screen position, labels it with the application icon, shows app names on hover, and tracks live resizes.
- `orbital.ui` adds `OrbitalIcon`, a reusable icon component tinted with the selected accent colour, with an option to preserve the source colours.
- `orbital.workspaces` reads window geometry and workspace membership from a live `hyprctl clients -j` poll instead of
  Hyprland's toplevel cache, which goes stale on resize because Hyprland emits no resize event for it.
- `install.sh` now asserts that every plugin's `entryPoints` target exists exactly once on disk. Omarchy's shell resolves
  those paths, not the installer, so a wrong path or a stale duplicate copy previously passed the whole test suite and
  only failed on screen.
- `orbital.lockscreen` is now bundled: a fork of `SirJul1337/omarchy-lock-explorer` (MIT), previously installed by hand
  and unknown to the installer, which therefore neither copied nor removed it. Orbital's changes are the plugin id/name
  and showing the real display name on the lock screen. See `docs/NOTICE.md`.

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
- `CREDITS.md` itemizes the provenance of the wallpaper that ships (one, `backgrounds/01-orbital-astronaut.png`);
  `docs/NOTICE.md` covers attribution and the limits of a pre-release.

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
