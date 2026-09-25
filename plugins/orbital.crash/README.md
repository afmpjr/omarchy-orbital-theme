# orbital.crash — themed crash dialog

Shows a "Process crashed: X" toast; clicking it opens a themed modal with the crash details and two buttons: **Dismiss** and
**Diagnose with AI**.

- **Kind:** `overlay` · **Entry point:** `Crash.qml` · **Version:** 1.1.0
- **Installed by:** `install.sh` (overlay + a systemd user drop-in)
- **UI contract:** [`orbital.ui`](../orbital.ui/README.md) (`OrbitalDialog` / `OrbitalTokens`)

## How a crash reaches the dialog

`install.sh` drops in `~/.config/systemd/user/omarchy-crash-watch.service.d/orbital.conf`, which replaces the `ExecStart` of
Omarchy's own `omarchy-crash-watch` with `orbital-crash-watch`. The watcher is the same; only the announcement changes.

```
process crashes -> orbital-crash-watch -> "Process crashed: X / View details" toast
                -> click -> modal (process, binary, signal, time, top stack frame, occurrence count)
                -> Dismiss, or Diagnose with AI (runs the stock omarchy-agent-crash with the same argv)
```

If the modal cannot be shown, the click falls back to starting the diagnosis directly.

## Language

Follows the system locale: `pt*` gives Portuguese, anything else English.

## Manual setup

```bash
mkdir -p ~/.config/systemd/user/omarchy-crash-watch.service.d
cp systemd/orbital.conf ~/.config/systemd/user/omarchy-crash-watch.service.d/orbital.conf
systemctl --user daemon-reload && systemctl --user try-restart omarchy-crash-watch
```

`install.sh --uninstall` removes the drop-in.

## License

MIT (see the repository `LICENSE`).
