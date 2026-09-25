# orbital.clock — clock with calendar popup

Date and time in the bar, with a calendar popup that carries the real reminders and weather.

- **Kind:** `bar-widget` · **Entry point:** `BarWidget.qml` (+ `Panel.qml` for the popup) · **Version:** 1.0.0
- **Installed by:** `install.sh --bar-widgets` (right section) or `install.sh --full`

## Options

Read from the widget entry in `.bar.layout` of `shell.json`:

| Key | Default | Meaning |
|-----|---------|---------|
| `format` | `dddd HH:mm` | Label in the bar |
| `formatAlt` | `d MMMM 'W'ww yyyy` | Long format used by the calendar popup |
| `verticalFormat` | — | Label when the bar is on a side edge |

Right-click cycles the common label formats, and the format you stop on is what the shell stores: it sticks across restarts
instead of reverting.

## Attribution

A modified clone of Omarchy's built-in `omarchy.clock` (MIT). See `docs/NOTICE.md`.

## License

MIT (see the repository `LICENSE`).
