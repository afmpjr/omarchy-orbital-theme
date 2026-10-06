# orbital.settings — setup center

Sidebar settings for the Orbital theme: accent (live swatches + custom hex),
bar, bar position, widgets, keyboard, wallpaper (theme + ~/Pictures thumbs),
avatar, transparency, gaps and extras, each with a live preview where it
matters (swatches, wallpaper thumbs, bar mock).

- **Kind:** `overlay` · **Entry point:** `Settings.qml` · **Version:** 1.0.0
- **Installed by:** `install.sh` (always). Opened after a successful install,
  from the account Appearance row (now a shortcut here), from the
  `Orbital Settings` apps-menu entry, or directly:
  `omarchy-shell shell toggle orbital.settings`

## Details

- Every choice is saved and applied immediately. Bar configuration is picked
  up by the running shell; Hyprland preferences reload the compositor config
  without restarting Quickshell.
- **Apply** reloads Hyprland and leaves Settings open.
- Keyboard shortcut styles are mutually exclusive: Default, Mac-style
  (Super/⌘ sends common Ctrl shortcuts to Linux apps; Alt remains Option), and
  Windows-style.
- The panel reads current Omarchy and Hyprland settings whenever it opens.
- Summon accepts `{"section": "<id>"}` to open on a specific tab.

## Attribution

Original work for this theme.

## License

MIT (see the repository `LICENSE`).
