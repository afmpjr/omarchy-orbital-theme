# orbital.launcher — app drawer

The centered drawer: search, categories, a Recommended section and a per-app context menu (pin, move to category, themed
uninstall confirmation).

- **Kinds:** `overlay`, `menu` · **Entry point:** `Launcher.qml` (+ `AppSearch.js`) · **Version:** 1.0.0
- **Installed by:** `install.sh` (always, as an overlay)

## Opening it

```bash
omarchy-shell shell toggle orbital.launcher
```

`install.sh --full` also rebinds **Super+S** to it (`hypr/orbital-bindings.lua`) and unbinds the stock Super+S action. Skip
with `--no-launcher-key` and bind it yourself.

If you forward keystrokes through `keyd`, Super+S arrives as Super *tap*; see `docs/keyd.md`.

## The uninstall confirmation

Uninstalling an app from the context menu shows a themed confirmation dialog built on the
[`orbital.ui`](../orbital.ui/README.md) contract instead of the stock one.

## License

MIT (see the repository `LICENSE`).
