#!/usr/bin/env bash
# End-to-end check on a clean Omarchy VM (project: omarchy-testbed).
# Resets the VM, installs the theme the way a user would (theme install + install.sh --full),
# applies it, opens the launcher and saves a screenshot.
#   scripts/e2e-testbed.sh [out.png]
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TB="${TESTBED:-/mnt/dados/projects/omarchy-testbed}/scripts/tb"
OUT="${1:-$REPO/docs/e2e-launcher.png}"
"$TB" reset; "$TB" up >/dev/null
echo -n "Waiting for the guest"; until "$TB" ssh true 2>/dev/null; do echo -n .; sleep 5; done; echo
until "$TB" ssh 'pgrep -x quickshell >/dev/null && pgrep -x Hyprland >/dev/null' 2>/dev/null; do sleep 3; done; sleep 8
"$TB" push "$REPO" omarchy-orbital-theme
ENVSET='export OMARCHY_PATH=/usr/share/omarchy XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr | head -1)'
"$TB" ssh "$ENVSET; omarchy theme install file:///home/tester/omarchy-orbital-theme >/dev/null 2>&1; cd ~/.config/omarchy/themes/orbital && ./install.sh --full >/tmp/install.log 2>&1; tail -3 /tmp/install.log"
sleep 10
"$TB" ssh "$ENVSET; hyprctl eval 'hl.monitor({ output = \"\", mode = \"1366x768@60\", position = \"auto\", scale = 1 })' >/dev/null; hyprctl dispatch 'hl.dsp.focus({ workspace = \"9\" })' >/dev/null; for i in 1 2 3 4; do hyprctl layers | grep -q orbital-launcher && break; omarchy-shell shell toggle orbital.launcher '{}'; sleep 3; done"
sleep 4; "$TB" shot "$OUT"
"$TB" ssh "$ENVSET; hyprctl configerrors | head -3; omarchy plugin list | grep -c 'orbital.*enabled'"
