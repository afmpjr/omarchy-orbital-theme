# orbital.run — Windows-style Run dialog

The Win+R dialog: a compact card with a focused command field, live suggestions and a
persistent MRU history. Exact executor first (Windows semantics), search surface stays
with [`orbital.launcher`](../orbital.launcher/README.md).

- **Kinds:** `overlay`, `menu` · **Entry point:** `Run.qml` (+ `AppSearch.js`) · **Version:** 1.0.0
- **Bound at:** **Super+R** — `orbital-keys-windows.lua` replaces the stock app-menu bind.

## What it understands

| Input | Meaning | How it runs |
|---|---|---|
| `https://…`, `www.…` | Browser URL | `uwsm-app -- xdg-open` |
| App id or name (`ghostty`, `files-native`…) | Installed .desktop app | `uwsm-app -- gtk-launch <id>.desktop` |
| `~/…`, `/path/…`, `./relative` | Folder or document | `xdg-open` (failure resurfaces via `notify-send`) |
| Anything on PATH (`htop -d 2`…) | Real command line | `bash -lc` detached, arguments/quoting intact |
| Not found | — | Inline error, nothing is recorded |

Fuzzy app matching comes from the first-party `AppSearch.js` (same port the launcher uses),
so `calc`, partial names and acronyms resolve like the launcher does. Prefix ordering:
apps first, then history substrings, then PATH binaries.

## Keys

| Key | Action |
|---|---|
| Enter | Run the selected suggestion (or the typed text as-is) |
| Up / Down | Suggestion list; with none open, recall commands from history (Win+R style) |
| Tab | Complete to the selected suggestion |
| Esc / Cancel / click outside | Close without running |

## History

Every successful run is prepended to `~/.local/state/orbital-run.json` (MRU, cap 30,
deduped) — the Windows `RunMRU` equivalent. Failed lookups never pollute it. Empty query
shows the recent entries.

## Integration notes

- Plugin dir is symlinked by `install.sh` (glob `orbital*`), same as the rest of the suite.
- `Super+R` — the bind lives in `~/.config/hypr/orbital-keys-windows.lua` (live) and
  `omarchy.settings/shell preference` packaged copy; the `windows-like` keybindings preset
  (`config/hypr/keybindings/windows-like.lua`) mirrors it, so switching presets keeps the
  dialog. The `mac` profile keeps the stock bind by design.
- `orbital.ui` is available for future restyling, but the card uses the shell's `Color.menu`
  / `Border.surfaceSpec` tokens directly, like the launcher does.

## License

MIT (see the repository `LICENSE`).
