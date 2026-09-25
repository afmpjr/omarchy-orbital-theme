# orbital.workspaces — workspace indicators

Numbered workspace chips for the bar, with the focused and the occupied ones styled apart.

- **Kind:** `bar-widget` · **Entry point:** `Workspaces.qml` · **Version:** 1.0.0
- **Installed by:** `install.sh --bar-widgets` (center section) or `install.sh --full`

## Details

- Occupancy comes from the workspace's toplevel list, so a workspace with only hidden windows still reads as occupied.
- The focused chip follows Hyprland's focused workspace, so it stays correct across monitors and special workspaces.
- Gaps adapt when the bar is vertical (`trailingGap` collapses), so the chips do not double the spacing on a side edge.

## Attribution

A modified clone of Omarchy's built-in `omarchy.workspaces` (MIT). See `docs/NOTICE.md`.

## License

MIT (see the repository `LICENSE`).
