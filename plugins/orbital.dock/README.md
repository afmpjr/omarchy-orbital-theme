# orbital.dock — dock in the bar

Pinned and running apps: click to launch or focus, a dot while running, a context menu for the usual actions.

- **Kind:** `bar-widget` · **Entry point:** `Dock.qml` · **Version:** 1.0.0
- **Installed by:** `install.sh --bar-widgets` (left section) or `install.sh --full`

## Pins

Pinned entries live in `~/.local/state/omarchy/orbital-dock.json`, **not** in the dock plugin's own state file, so this dock
and the stock `omarchy.dock` never share or race on the same list.

`install.sh --full` creates the file on first run from what is actually installed (default browser, terminal, file manager),
and only when you have no pins yet.

## Attribution

Adapted from `claudsondouglas/arc.dock` (MIT, Copyright (c) 2026 Claudson): its app grouping and window matching. The
original license text is kept in `LICENSE-arc.dock`, as MIT requires. See `docs/NOTICE.md`.

## License

MIT (see the repository `LICENSE`).
