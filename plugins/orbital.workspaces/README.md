# orbital.workspaces — workspace indicators

Numbered workspace previews for the bar. Occupied workspaces show proportionally positioned window miniatures with application icons; the focused workspace is highlighted.

- **Kind:** `bar-widget` · **Entry point:** `Workspaces.qml` · **Version:** 1.0.0
- **Installed by:** `install.sh --bar-widgets` (center section) or `install.sh --full`

## Details

- Occupancy comes from the workspace's toplevel list, so a workspace with only hidden windows still reads as occupied.
- The focused chip follows Hyprland's focused workspace, so it stays correct across monitors and special workspaces.
- Application icons identify each window, and hovering a workspace shows the application names.
- Window geometry is refreshed while resizing, so the previews track live layout changes.
- Gaps adapt when the bar is vertical (`trailingGap` collapses), so the chips do not double the spacing on a side edge.

## Attribution

A modified clone of Omarchy's built-in `omarchy.workspaces` (MIT). See `docs/NOTICE.md`.

## License

MIT (see the repository `LICENSE`).
