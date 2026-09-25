#!/usr/bin/env bash
# Orbital installer: theme companions that `omarchy theme install` cannot ship.
#
#   omarchy theme install https://github.com/<you>/omarchy-orbital-theme   # the theme itself
#   ./install.sh [--full] [--keyboard-layouts us,br] [--bar-widgets] [--no-restart] [--dry-run]      # plugins + Hyprland glass
#   ./install.sh --uninstall
#
#   --full  also reproduces the author's desktop: Orbital floating bar (bottom, half-size gap),
#           dock left / workspaces center / divider + clock right, Super+S launcher binding,
#           8/12 window gaps, text size 10, keyboard layout widget + Alt+Shift and default dock pins. Your shell.json is backed up first.
#
# Idempotent. Never edits shell.json by hand (uses `omarchy plugin enable`),
# backs up anything it replaces OUTSIDE the plugins folder (the shell scans it).
set -euo pipefail

export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
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
WIDGETS=("orbital.dock:left" "orbital.workspaces:center" "orbital.keyboard:right" "orbital.clock:right")
EXTRA_WIDGETS=(orbital.divider)

DRY=0 RESTART=1 BAR=0 UNINSTALL=0 FULL=0 KBLAYOUTS=
while (( $# )); do
  a=$1; shift
  case $a in
    --dry-run) DRY=1 ;; --no-restart) RESTART=0 ;; --bar-widgets) BAR=1 ;; --full) FULL=1; BAR=1 ;;
    --keyboard-layouts) KBLAYOUTS="${1:?--keyboard-layouts needs a list, e.g. us,br}"; shift ;; --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n 2,14p "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say() { echo "==> $*"; }
nap() { [[ ${ORBITAL_INSTALL_NO_WAIT:-} == 1 ]] || sleep "$1"; }  # tests skip the waits
run() { if (( DRY )); then echo "    [dry-run] $*"; else "$@"; fi; }
have_omarchy() { command -v omarchy >/dev/null 2>&1; }

uninstall() {
  say "Removing Orbital plugins, Hyprland hook and crash drop-in"
  for id in "${OVERLAYS[@]}" "${LIBS[@]}" orbital.floating-bar "${EXTRA_WIDGETS[@]}" "${WIDGETS[@]%%:*}"; do
    have_omarchy && run omarchy plugin disable "$id" 2>/dev/null || true
    run rm -rf "$PLUGINS/$id"
  done
  run rm -f "$HYPR/orbital.lua" "$HYPR/orbital-gaps.lua" "$HYPR/orbital-bindings.lua" "$HYPR/orbital-keyboard.lua" "$DROPIN/orbital.conf"
  [[ -f $HYPR/hyprland.lua ]] && run sed -i '/-- orbital$/d' "$HYPR/hyprland.lua"
  say "shell.json is not reverted automatically; restore a backup: $CFG/omarchy/shell.json.bak-orbital-*"
  systemctl --user daemon-reload 2>/dev/null || true
  say "Done. The theme itself: omarchy theme remove orbital. Baseline kept in $BASE."
}

if (( UNINSTALL )); then uninstall; exit 0; fi

desktop_id() { # first installed .desktop among candidates
  local c; for c in "$@"; do
    for d in /usr/share/applications ~/.local/share/applications; do [[ -f $d/$c.desktop ]] && { echo "$c"; return; }; done
  done
}

full_shell_json() {
  say "Full desktop: bar and layout in shell.json"
  local sj="$CFG/omarchy/shell.json"
  run mkdir -p "$CFG/omarchy"
  if [[ ! -f $sj ]]; then run cp "${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json" "$sj"; fi
  run cp "$sj" "$sj.bak-orbital-$STAMP"
  if (( ! DRY )); then
    local tmp; tmp="$(mktemp)"
    jq '
      .bar = (.bar // {}) |
      .bar.id = "orbital.floating-bar" | .bar.position = "bottom" | .bar.transparent = false |
      .bar.cornerRadius = 10 | .bar.floatGapScale = 0.5 | .bar.centerAnchor = "orbital.workspaces" |
      (.bar.layout // {}) as $l |
      ([($l.left // [])[], ($l.center // [])[], ($l.right // [])[]]) as $all |
      ($all | map(select(.id == "omarchy.indicators"))) as $ind |
      ($l.right // []) as $right |
      .bar.layout = {
        left:   [{id: "orbital.dock"}],
        center: [{id: "orbital.workspaces"}],
        right:  ( ($right | map(select(.id == "omarchy.tray")))
                + $ind
                + ($right | map(select(.id != "omarchy.tray" and .id != "omarchy.indicators"
                                        and .id != "orbital.divider" and .id != "orbital.keyboard" and .id != "orbital.clock" and .id != "omarchy.clock")))
                + [{id: "orbital.keyboard"}, {id: "orbital.divider"},
                   {id: "orbital.clock", format: "HH:mm", formatAlt: "d MMMM '"'"'W'"'"'ww yyyy", verticalFormat: "HH\n—\nmm"}] )
      }
    ' "$sj" > "$tmp" && cat "$tmp" > "$sj" && rm -f "$tmp"
  fi
}

# Alt+Shift switches layouts (xkb grp:alt_shift_toggle). Uses the layouts you already have in
# ~/.config/hypr/input.lua, or --keyboard-layouts us,br. Written to its own file, loaded last.
keyboard_setup() {
  local input="$HYPR/input.lua" layouts="$KBLAYOUTS" opts="compose:caps,shift:both_capslock_cancel"
  if [[ -f $input ]]; then
    [[ -n $layouts ]] || layouts="$(grep -E '^[[:space:]]*kb_layout[[:space:]]*=' "$input" | head -1 | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/')"
    local existing; existing="$(grep -E '^[[:space:]]*kb_options[[:space:]]*=' "$input" | head -1 | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/')"
    [[ -n $existing ]] && opts="$existing"
  fi
  if [[ $layouts != *,* ]]; then
    echo "    Keyboard: only one layout configured; pass --keyboard-layouts us,br to enable switching (the tray widget stays hidden until then)."
    return 0
  fi
  opts="$(echo "$opts" | tr ',' '\n' | grep -v '^grp:' | paste -sd, -)"
  opts="${opts:+$opts,}grp:alt_shift_toggle"
  say "Keyboard layouts: $layouts (Alt+Shift switches)"
  run mkdir -p "$HYPR"
  if (( ! DRY )); then
    printf -- '-- Orbital keyboard: layouts + Alt+Shift toggle (loaded last). Edit or delete freely.\nhl.config({ input = { kb_layout = "%s", kb_options = "%s" } })\n' "$layouts" "$opts" > "$HYPR/orbital-keyboard.lua"
    grep -qF 'hypr.orbital-keyboard' "$HYPR/hyprland.lua" || printf 'require("hypr.orbital-keyboard") -- orbital\n' >> "$HYPR/hyprland.lua"
  fi
}

full_setup() {
  say "Full desktop: bindings, gaps, text size, dock pins"
  # Text size the layout was tuned at (shell, GTK and terminals), like the author's machine.
  run omarchy display text size 10 || echo "    (could not set the text size)"
  # Hyprland: bindings + gaps (gaps go BEFORE Omarchy's toggles so the gaps toggle still wins).
  run cp "$REPO/hypr/orbital-bindings.lua" "$HYPR/orbital-bindings.lua"
  run cp "$REPO/hypr/orbital-gaps.lua" "$HYPR/orbital-gaps.lua"
  if [[ -f $HYPR/hyprland.lua ]] && (( ! DRY )); then
    grep -qF 'hypr.orbital-bindings' "$HYPR/hyprland.lua" || printf 'require("hypr.orbital-bindings") -- orbital\n' >> "$HYPR/hyprland.lua"
    if ! grep -qF 'hypr.orbital-gaps' "$HYPR/hyprland.lua"; then
      if grep -q 'require("default.hypr.toggles")' "$HYPR/hyprland.lua"; then
        sed -i 's|^require("default.hypr.toggles")|require("hypr.orbital-gaps") -- orbital\n&|' "$HYPR/hyprland.lua"
      else printf 'require("hypr.orbital-gaps") -- orbital\n' >> "$HYPR/hyprland.lua"; fi
    fi
  fi
  keyboard_setup
  # Dock pins: only if the user has none yet; from what is actually installed.
  local pins="$HOME/.local/state/omarchy/orbital-dock.json"
  if [[ ! -f $pins ]] && (( ! DRY )); then
    local b t f entries=()
    b="$(xdg-settings get default-web-browser 2>/dev/null | sed 's/\.desktop$//')"
    t="$(desktop_id com.mitchellh.ghostty Alacritty kitty foot)"
    f="$(desktop_id org.gnome.Nautilus org.kde.dolphin thunar)"
    for e in "$b" "$t" "$f"; do [[ -n $e ]] && entries+=("$e"); done
    if (( ${#entries[@]} )); then
      mkdir -p "$(dirname "$pins")"
      printf '%s\n' "${entries[@]}" | jq -R '{key: (. | ascii_downcase), entry: .}' | jq -s '{version: 1, pinned: .}' > "$pins"
    fi
  fi
}

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
     --exclude=./README.md --exclude=./CHANGELOG.md --exclude=./LICENSE* --exclude='*.png' --exclude='*.jpg' .) | tar xf - -C "$BASE"
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

# 6. Enable plugins through Omarchy's own CLI. A fresh Omarchy has no ~/.config/omarchy/shell.json
#    and `plugin enable` then silently records nothing, so create it from the defaults first.
SJ="$CFG/omarchy/shell.json"
if [[ ! -f $SJ ]]; then
  say "Creating $SJ from Omarchy's defaults"
  run mkdir -p "$CFG/omarchy"; run cp "$OMARCHY_PATH/config/omarchy/shell.json" "$SJ"; run chmod 644 "$SJ"
fi
if (( FULL )); then full_shell_json; nap 3; fi
if (( ! DRY )); then omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true; nap 2; fi
say "Enabling plugins"
enable_verified() { # `plugin enable` talks to the running shell; confirm it stuck, retry if not
  local id="$1" n
  for n in 1 2 3 4 5; do
    omarchy plugin enable "$id" >/dev/null 2>&1 || true
    omarchy plugin list 2>/dev/null | grep -E "^$id +enabled" >/dev/null && { echo "    enabled $id"; return 0; }
    nap 2
  done
  echo "    (could not enable $id)"; return 1
}
for id in "${OVERLAYS[@]}"; do if (( DRY )); then echo "    [dry-run] enable $id"; else enable_verified "$id" || true; fi; done
if (( BAR )); then
  for w in "${WIDGETS[@]}"; do run omarchy plugin enable "${w%%:*}" --section "${w##*:}" || echo "    (could not place ${w%%:*})"; done
else
  echo "    Bar widgets not touched. To use them: ./install.sh --bar-widgets  (dock left, workspaces center, clock right)"
fi

if (( FULL )); then full_setup; fi

if (( RESTART )) && (( ! DRY )); then say "Restarting the shell"; omarchy restart shell || true; fi
say "Now apply the theme: omarchy theme set Orbital"
echo "    Optional: set your avatar with  ~/.config/omarchy/plugins/orbital.account/orbital-avatar <image>"
