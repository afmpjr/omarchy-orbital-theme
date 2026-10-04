# orbital.workspaces — workspace indicators

Numbered workspace previews for the bar. Occupied workspaces show proportionally positioned window miniatures with application icons; the focused workspace is highlighted.

- **Kind:** `bar-widget` · **Entry point:** `Workspaces.qml` · **Version:** 1.0.0
- **Installed by:** `install.sh --bar-widgets` (center section) or `install.sh --full`

## Details

- Occupancy comes from the live `hyprctl clients -j` snapshot the widget already polls, so a window that Hyprland's
  toplevel cache has not picked up yet still shows up in its workspace.
- The focused chip follows Hyprland's focused workspace, so it stays correct across monitors and special workspaces.
- Application icons identify each window, and hovering a workspace shows the application names.
- Window geometry and workspace membership both come from that poll, so previews track resize, move and
  close instantly — Hyprland emits no resize event for the toplevel cache to refresh from.
- Gaps adapt when the bar is vertical (`trailingGap` collapses), so the chips do not double the spacing on a side edge.
- Drag a chip onto another chip to **swap the two workspaces' windows**: the dragged chip lifts off as a
  ghost of its own pixels and the drop target gets the accent border; releasing anywhere else cancels.
  Clicks still switch workspaces exactly as before. The move sequence runs through the companion script
  `orbital-workspace-swap <ws-a> <ws-b>` (via a scratch workspace, so neither side ever merges into the
  other), which is also how the drop path is tested headlessly: `orbital-workspace-swap 2 4`.

## Attribution

A modified clone of Omarchy's built-in `omarchy.workspaces` (MIT). See `docs/NOTICE.md`.

## License

MIT (see the repository `LICENSE`).
