#!/usr/bin/env bash
# Orbital installer: theme companions that `omarchy theme install` cannot ship.
#
#   omarchy theme install https://github.com/<you>/omarchy-orbital-theme   # the theme itself
#   ./install.sh [--bar-widgets] [--no-restart] [--dry-run]                # plugins + Hyprland glass
#   ./install.sh --uninstall
#
# Idempotent. Never edits shell.json by hand (uses `omarchy plugin enable`),
# backs up anything it replaces OUTSIDE the plugins folder (the shell scans it).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$HOME/.config"
PLUGINS="$CFG/omarchy/plugins"
BACKUPS="$CFG/omarchy/plugin-backups"
BASE="$HOME/.local/state/omarchy/orbital-accent-base"
HYPR="$CFG/hypr"
DROPIN="$CFG/systemd/user/omarchy-crash-watch.service.d"
MARK='require("hypr.orbital") -- orbital'
STAMP="$(date +%Y%m%dT%H%M%S)"

OVERLAYS=(orbital.launcher orbital.account orbital.appearance orbital.worldclock orbital.crash)
LIBS=(orbital.ui)
WIDGETS=("orbital.dock:left" "orbital.workspaces:center" "orbital.clock:right")
EXTRA_WIDGETS=(orbital.divider)

DRY=0 RESTART=1 BAR=0 UNINSTALL=0
for a in "$@"; do
  case $a in
    --dry-run) DRY=1 ;; --no-restart) RESTART=0 ;; --bar-widgets) BAR=1 ;; --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n 2,9p "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say() { echo "==> $*"; }
run() { if (( DRY )); then echo "    [dry-run] $*"; else "$@"; fi; }
have_omarchy() { command -v omarchy >/dev/null 2>&1; }

uninstall() {
  say "Removing Orbital plugins, Hyprland hook and crash drop-in"
  for id in "${OVERLAYS[@]}" "${LIBS[@]}" "${EXTRA_WIDGETS[@]}" "${WIDGETS[@]%%:*}"; do
    have_omarchy && run omarchy plugin disable "$id" 2>/dev/null || true
    run rm -rf "$PLUGINS/$id"
  done
  run rm -f "$HYPR/orbital.lua" "$DROPIN/orbital.conf"
  [[ -f $HYPR/hyprland.lua ]] && run sed -i '/-- orbital$/d' "$HYPR/hyprland.lua"
  systemctl --user daemon-reload 2>/dev/null || true
  say "Done. The theme itself: omarchy theme remove orbital. Baseline kept in $BASE."
}

if (( UNINSTALL )); then uninstall; exit 0; fi

# 1. Requirements (fail early, name what is missing).
missing=()
for c in python3 jq bash; do command -v "$c" >/dev/null || missing+=("$c"); done
have_omarchy || missing+=("omarchy")
if (( ${#missing[@]} )); then echo "Missing requirements: ${missing[*]}" >&2; exit 1; fi

# 2. Plugins (own ids only; backups go outside the scanned folder).
say "Installing plugins into $PLUGINS"
run mkdir -p "$PLUGINS" "$BACKUPS"
for d in "$REPO"/plugins/*/; do
  id="$(basename "$d")"
  if [[ -d $PLUGINS/$id ]] && ! diff -rq "$d" "$PLUGINS/$id" >/dev/null 2>&1; then
    run mv "$PLUGINS/$id" "$BACKUPS/$id.$STAMP"
  fi
  [[ -d $PLUGINS/$id ]] || run cp -r "$d" "$PLUGINS/$id"
  run chmod +x "$PLUGINS/$id"/orbital-* 2>/dev/null || true
done

# 3. Pristine (blue) theme copy: the accent picker regenerates the theme from it.
say "Creating the accent picker baseline in $BASE"
run mkdir -p "$BASE"
if (( ! DRY )); then
  (cd "$REPO" && tar cf - --exclude=./plugins --exclude=./hypr --exclude=./systemd --exclude=./scripts \
     --exclude=./docs --exclude=./backgrounds --exclude=./.git --exclude=./install.sh \
     --exclude=./README.md --exclude=./CHANGELOG.md --exclude=./LICENSE* .) | tar xf - -C "$BASE"
fi

# 4. Hyprland glass/blur/animations (theme .lua files are dropped by `theme install`).
say "Installing the Hyprland part ($HYPR/orbital.lua)"
run mkdir -p "$HYPR"
run cp "$REPO/hypr/orbital.lua" "$HYPR/orbital.lua"
if [[ -f $HYPR/hyprland.lua ]] && ! grep -qF "$MARK" "$HYPR/hyprland.lua"; then
  run cp "$HYPR/hyprland.lua" "$HYPR/hyprland.lua.bak-orbital-$STAMP"
  if (( ! DRY )); then printf '\n-- Orbital glass, borders, animations (loaded last so it wins over earlier settings).\n%s\n' "$MARK" >> "$HYPR/hyprland.lua"; fi
fi

# 5. Crash modal: swap the crash watcher for the Orbital one.
say "Installing the crash-watch drop-in"
run mkdir -p "$DROPIN"
run cp "$REPO/systemd/orbital.conf" "$DROPIN/orbital.conf"
if (( ! DRY )); then systemctl --user daemon-reload 2>/dev/null || true; systemctl --user try-restart omarchy-crash-watch 2>/dev/null || true; fi

# 6. Enable plugins through Omarchy's own CLI.
say "Enabling plugins"
for id in "${OVERLAYS[@]}"; do run omarchy plugin enable "$id" || echo "    (could not enable $id)"; done
if (( BAR )); then
  for w in "${WIDGETS[@]}"; do run omarchy plugin enable "${w%%:*}" --section "${w##*:}" || echo "    (could not place ${w%%:*})"; done
else
  echo "    Bar widgets not touched. To use them: ./install.sh --bar-widgets  (dock left, workspaces center, clock right)"
fi

if (( RESTART )) && (( ! DRY )); then say "Restarting the shell"; omarchy restart shell || true; fi
say "Now apply the theme: omarchy theme set Orbital"
