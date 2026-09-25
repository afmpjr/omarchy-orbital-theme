# orbital.divider — hairline between widget groups

A thin separator, so the bar can be split into readable groups (launchers | workspaces | system).

- **Kind:** `bar-widget` · **Entry point:** `Divider.qml` · **Version:** 1.0.0
- **Installed by:** `install.sh --bar-widgets` (right section, before the clock)

## Options

None. Size and color come from the active theme (`Style` / the bar section tokens), so it follows the accent and glass
changes made in [`orbital.appearance`](../orbital.appearance/README.md).

Multiple dividers are allowed: `allowMultiple` is true, so place one wherever a group ends.

## License

MIT (see the repository `LICENSE`).
