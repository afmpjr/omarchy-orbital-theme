#!/usr/bin/env bash
# End-to-end check on a clean Omarchy VM (project: omarchy-testbed).
# Resets the VM, installs the theme the way a user would (theme install + install.sh --full),
# applies it, opens the launcher and saves a screenshot.
#   scripts/e2e-testbed.sh [out.png]
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# The VM harness lives in a separate repository; point TESTBED at its scripts/tb.
TB="${TESTBED:-$HOME/.local/share/omarchy-testbed}/scripts/tb"
[[ -x $TB ]] || { echo "Set TESTBED to an omarchy-testbed checkout (expected $TB to be executable)." >&2; exit 1; }
OUT="${1:-$REPO/docs/e2e-launcher.png}"
"$TB" reset; "$TB" up >/dev/null
echo -n "Waiting for the guest"; until "$TB" ssh true 2>/dev/null; do echo -n .; sleep 5; done; echo
until "$TB" ssh 'pgrep -x quickshell >/dev/null && pgrep -x Hyprland >/dev/null' 2>/dev/null; do sleep 3; done; sleep 8
"$TB" push "$REPO" omarchy-orbital-theme
ENVSET='export OMARCHY_PATH=/usr/share/omarchy XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr | head -1)'
"$TB" ssh "$ENVSET; omarchy theme install file:///home/tester/omarchy-orbital-theme >/dev/null 2>&1; cd ~/.config/omarchy/themes/orbital && ./install.sh --full --keyboard-layouts us,br >/tmp/install.log 2>&1; tail -3 /tmp/install.log"
sleep 10
"$TB" ssh "$ENVSET; hyprctl eval 'hl.monitor({ output = \"\", mode = \"1366x768@60\", position = \"auto\", scale = 1 })' >/dev/null; hyprctl dispatch 'hl.dsp.focus({ workspace = \"9\" })' >/dev/null; for i in 1 2 3 4; do hyprctl layers | grep -q orbital-launcher && break; omarchy-shell shell toggle orbital.launcher '{}'; sleep 3; done"
sleep 4; "$TB" shot "$OUT"
"$TB" ssh "$ENVSET; hyprctl configerrors | head -3; omarchy plugin list | grep orbital"
LIST="$("$TB" ssh "$ENVSET; omarchy plugin list")"
BAR="$("$TB" ssh "$ENVSET; jq -r .bar.id ~/.config/omarchy/shell.json")"
[[ $BAR == orbital.floating-bar ]] || { echo "FAIL: --full should select orbital.floating-bar, got '$BAR'"; exit 1; }
DISABLED="$(grep -c 'orbital.*disabled' <<<"$LIST" || true)"
BAR_ON="$(grep -c 'orbital\.floating-bar.*enabled' <<<"$LIST" || true)"
OTHER_OFF="$(grep -c '^orbital\.bar .*disabled' <<<"$LIST" || true)"
[[ $BAR_ON == 1 ]] || { echo "FAIL: --full should leave orbital.floating-bar enabled"; exit 1; }
[[ $OTHER_OFF == 1 ]] || { echo "FAIL: the unused bar alternative should be the only disabled one"; exit 1; }
[[ $DISABLED == 1 ]] || { echo "FAIL: $DISABLED orbital plugin(s) disabled, expected only the inactive bar"; exit 1; }
echo "all orbital plugins enabled except the inactive bar alternative (bar.id=$BAR)"
