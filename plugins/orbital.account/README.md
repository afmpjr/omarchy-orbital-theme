# orbital.account — profile card

Overlay with the user's name and email, quick links to the real settings panels, and the power actions (lock, logout,
reboot, shutdown).

- **Kind:** `overlay` · **Entry point:** `Account.qml` · **Version:** 1.0.0
- **Installed by:** `install.sh` (always, as an overlay)

## Identity

Nothing is hardcoded. The name and email come from the identity cache used by the lock screen, falling back to
`git config --global user.name` / `user.email`, and finally to `$USER`.

## Avatar

The card and the dock read `~/.config/omarchy/avatar.png` when it exists; otherwise the Omarchy icon is shown. The bundled
helper sets it:

```bash
~/.config/omarchy/plugins/orbital.account/orbital-avatar ~/pictures/me.jpg   # cropped to 256x256 with ImageMagick
~/.config/omarchy/plugins/orbital.account/orbital-avatar --github            # needs `gh auth login`
~/.config/omarchy/plugins/orbital.account/orbital-avatar --reset
```

`omarchy-shell` caches the image for the session: restart the shell (`omarchy restart shell`) to see the change. The script
does that for you unless `--no-restart` is passed.

## License

MIT (see the repository `LICENSE`).
