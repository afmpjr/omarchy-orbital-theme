# orbital.run — Windows-style Run dialog

The Win+R dialog: a compact card anchored at the bottom-left corner (above the bar) with a
focused command field, live suggestions and a persistent MRU history. Exact executor first
(Windows semantics), while the search surface stays with
[`orbital.launcher`](../orbital.launcher/README.md).

- **Kinds:** `overlay`, `menu` · **Entry point:** `Run.qml` (+ `AppSearch.js`) · **Version:** 1.0.9
- **Bound at:** **Super+R** — `orbital-keys-windows.lua` unbinds the stock bind (`hl.unbind("SUPER + R")`) and binds `omarchy-shell shell toggle orbital.run`.

## What it understands

| Input | Meaning | How it runs |
|---|---|---|
| `https://…`, `www.…` | Browser URL | `uwsm-app -- xdg-open <url>` |
| App id or name (`ghostty`, `Visual Studio Code`…) | Installed GUI `.desktop` app | `shell.appLibrary.launch` or `uwsm-app -- gtk-launch <id>.desktop` |
| `~/…`, `/path/…`, `./relative` | Folder or document | `xdg-open` (failure resurfaces via `notify-send`) |
| Anything on `PATH` (`ping 8.8.8.8`, `ip a`, `htop`…) | CLI command line | Opens a floating terminal window (`setsid uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.terminal --title="Run: <cmd>" -e bash -lc 'eval -- "$1"...'`); stays open with `[exit N] Press any key to close...` when exit code != 130 |
| Not found | Invalid command | Inline error (`Could not find “…”`), dialog stays open, nothing is recorded |

Fuzzy app matching comes from the first-party `AppSearch.js` (same port the launcher uses),
so `calc`, partial names (`vis` -> `Visual Studio Code`) and reverse-DNS desktop IDs
(`org.gnome.Nautilus.desktop`) resolve accurately without false-positive launches on invalid
CLI commands. Prefix ordering: apps first, then history substrings, then `PATH` binaries.

## Keys & Actions

| Key / Control | Action |
|---|---|
| `Enter` / `OK` button / `↵ Run` pill | Run the selected suggestion or typed command |
| `Up` / `Down` / `↑↓ History` pill | Navigate suggestion list; with 0–1 items, cycle MRU history (Win+R style) |
| `Tab` / `TAB Complete` pill | Complete input to the selected suggestion (pressing `Tab` again cycles to the next suggestion) |
| `Esc` / `ESC` badge / `Cancel` button / click outside | Close without running |

## History

Every successful run is prepended to `~/.local/state/orbital-run.json` (MRU, cap 30,
deduped) — the Windows `RunMRU` equivalent. Failed lookups never pollute it. Empty query
shows up to 6 recent entries.

## Integration notes

- Plugin dir is installed by `install.sh` (`OVERLAYS` array and `orbital*` glob), same as the rest of the suite.
- `Super+R` — the bind lives in `hypr/orbital-keys-windows.lua` and `plugins/orbital.settings/orbital-keys-windows.lua` (`--windows-keys` preset), as well as `~/.dotfiles/config/hypr/keybindings/windows-like.lua`.
- Uses `orbital.ui`'s vector SVG fallback (`application-x-executable-symbolic.svg`) so generic command/history rows never fall back to low-contrast raster icons.

## License

MIT (see the repository `LICENSE`).
