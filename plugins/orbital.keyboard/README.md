# orbital.keyboard — keyboard layout in the tray

Country flag of the active layout; click for a dropdown to switch. Useful as soon as you have more than one layout: with a
single layout the widget stays hidden.

- **Kind:** `bar-widget` · **Entry point:** `Keyboard.qml` · **Version:** 1.0.0
- **Installed by:** `install.sh --bar-widgets` (right section) or `install.sh --full`

## Alt+Shift

`install.sh` also writes `~/.config/hypr/orbital-keyboard.lua` (loaded last from `hyprland.lua`) with two **release** binds,
`ALT+SHIFT+Shift_L` and `ALT+SHIFT+Alt_L`, both running `hyprctl switchxkblayout all next`. Release binds are used because
xkb's own `grp:alt_shift_toggle` only fires when Alt goes down while Shift is already held, so the usual Alt-then-Shift does
nothing. The installer drops any `grp:` option from `kb_options` for the same reason.

Layouts come from your existing `~/.config/hypr/input.lua`, or from `--keyboard-layouts us,br`. Skip with `--no-alt-shift`.

## Flags

`flags/*.svg` are from `lipis/flag-icons` (MIT, Copyright (c) 2013 Panayiotis Lipiridis); the license text is in
`LICENSE-flag-icons`. The widget itself is based on Omarchy's keyboard-layout widget (MIT).

## License

MIT (see the repository `LICENSE`).
