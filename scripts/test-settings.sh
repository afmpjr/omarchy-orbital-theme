#!/usr/bin/env bash
# Exercise immediate settings changes with isolated config and command stubs.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" PATH="$T/bin:$PATH"
PLUGINS="$HOME/.config/omarchy/plugins"
HYPR="$HOME/.config/hypr"
mkdir -p "$T/bin" "$PLUGINS/orbital.settings" "$PLUGINS/orbital.account" \
  "$PLUGINS/orbital.appearance" "$HOME/.local/state/omarchy" "$HYPR"
cp "$REPO/plugins/orbital.settings/orbital-settings-change" "$PLUGINS/orbital.settings/"
cp "$REPO/plugins/orbital.settings/orbital-settings-apply" "$PLUGINS/orbital.settings/"
cp "$REPO/plugins/orbital.settings/orbital-settings-state" "$PLUGINS/orbital.settings/"
cp "$REPO/plugins/orbital.settings/orbital-keys-"*.lua "$PLUGINS/orbital.settings/"
cp "$REPO/plugins/orbital.account/orbital-widgets-lock" "$PLUGINS/orbital.account/"
cp "$REPO/plugins/orbital.account/orbital-avatar" "$PLUGINS/orbital.account/"
chmod +x "$PLUGINS/orbital.settings/"orbital-settings-* "$PLUGINS/orbital.account/"*
cat > "$PLUGINS/orbital.appearance/orbital-accent.py" <<'PY'
import sys
open(__import__("os").path.expanduser("~/accent.log"), "w").write(sys.argv[1])
PY
cat > "$T/bin/omarchy" <<'STUB'
#!/usr/bin/env bash
printf 'omarchy %s\n' "$*" >> "$HOME/commands.log"
STUB
cat > "$T/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >> "$HOME/commands.log"
STUB
chmod +x "$T/bin/omarchy" "$T/bin/hyprctl"
change() { "$PLUGINS/orbital.settings/orbital-settings-change" "$@" >/dev/null; }
ok() { echo "ok   - $1"; }

printf 'require("default.hypr.omarchy")\n' > "$HYPR/hyprland.lua"
change accent purple
[[ $(cat "$HOME/accent.log") == purple ]]
change bar orbital.bar
change bar-position top
change transparency true
change divider true
change widget-lock false
[[ $(cat "$HOME/.local/state/omarchy/orbital-widgets-lock") == 0 ]]
change keyboard us,br
grep -q 'kb_layout = "us,br"' "$HYPR/orbital-keyboard.lua"
change gaps 4,4
grep -q 'gaps_in = 4, gaps_out = 4' "$HYPR/orbital-gaps.lua"
grep -q 'hypr.orbital-keyboard' "$HYPR/hyprland.lua"
grep -q 'hypr.orbital-gaps' "$HYPR/hyprland.lua"
ok "accent, bar, widgets, keyboard and gaps apply immediately"

touch "$T/wallpaper.png"
if command -v magick >/dev/null; then
  magick -size 1x1 xc:white "$T/avatar.png"
else
  printf 'avatar test file\n' > "$T/avatar.png"
fi
change wallpaper "$T/wallpaper.png"
change avatar "file:$T/avatar.png"
[[ -f "$HOME/.config/omarchy/avatar.png" ]]
change avatar clear
[[ ! -f "$HOME/.config/omarchy/avatar.png" ]]
ok "wallpaper and avatar apply without shell restart"

change shortcuts mac
grep -q 'hypr.orbital-keys-mac' "$HYPR/hyprland.lua"
grep -q 'send_shortcut' "$HYPR/orbital-keys-mac.lua"
change shortcuts windows
grep -q 'hypr.orbital-keys-windows' "$HYPR/hyprland.lua"
[[ ! -e "$HYPR/orbital-keys-mac.lua" ]]
change shortcuts default
! grep -q 'orbital-keys-' "$HYPR/hyprland.lua"
[[ ! -e "$HYPR/orbital-keys-windows.lua" ]]
ok "shortcut profiles replace one another and default restores stock bindings"

printf '{"version":1,"bar":{"id":"orbital.bar","position":"top","transparent":true,"layout":{"right":[]}}}\n' > "$HOME/.config/omarchy/shell.json"
change shortcuts mac
state=$("$PLUGINS/orbital.settings/orbital-settings-state")
[[ $(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["shortcutStyle"])' "$state") == mac ]]
ok "current shortcut profile loads into the settings state"

printf '{"pinned":[]}\n' > "$HOME/.local/state/omarchy/orbital-dock.json"
change reset-pins true
[[ ! -e "$HOME/.local/state/omarchy/orbital-dock.json" ]]
apply_output=$("$PLUGINS/orbital.settings/orbital-settings-apply")
[[ $apply_output == "Applied. Setup remains open." ]]
! grep -q 'restart shell' "$HOME/commands.log"
ok "Apply reloads Hyprland without restarting the shell"

grep -q 'Array.isArray(data.pinned)' "$REPO/plugins/orbital.dock/Dock.qml"
grep -q 'root.pinned = out' "$REPO/plugins/orbital.dock/Dock.qml"
ok "dock state preserves an intentionally empty pin list"
