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

- Choices are staged as pending values; nothing touches the system until
  **Apply all**, which runs `orbital-settings-apply` once with the whole set
  and then reloads Hyprland + restarts the shell exactly once. Two exceptions
  stay live, like everywhere else they appear: accent swatches and the widgets
  lock switch.
- Summon accepts `{"section": "<id>"}` to open on a specific tab.

## Attribution

Original work for this theme.

## License

MIT (see the repository `LICENSE`).
