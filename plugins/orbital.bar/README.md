# orbital.bar — self-contained Orbital bar

A floating glass bar with the dock, workspace pills and system controls built in: one plugin instead of a bar plus four
widgets. It is the earlier Orbital bar design, kept as an **alternative** to
[`orbital.floating-bar`](../orbital.floating-bar/README.md).

- **Kind:** `bar` · **Entry point:** `Bar.qml` · **Version:** 1.0.0
- **Installed by:** `install.sh` (copied with the other plugins; only the bar named in `shell.json` is loaded)

## Pick one bar

Both plugins declare `kind: bar`, and the shell loads **only** the one referenced by `.bar.id` in
`~/.config/omarchy/shell.json`; the other shows up as an option in the bar menu. `install.sh --full` writes
`orbital.floating-bar`. To use this one instead:

```bash
omarchy plugin enable orbital.bar     # sets .bar.id
omarchy restart shell
```

Running both at once is not possible by design — there is one bar.

## Options

Read from `.bar` in `shell.json`:

| Key | Default | Meaning |
|-----|---------|---------|
| `position` | `bottom` | `bottom`, `top`, `left`, `right` |
| `floatGap` | `12` | Gap between the bar and the screen edge, px |
| `cornerRadius` | `16` | Corner radius, px |

Unlike the fork, this bar has no `floatGapScale` option (that is the `orbital.floating-bar` addition).

## License

MIT (see the repository `LICENSE`). Original Orbital code.
