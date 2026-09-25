#!/usr/bin/env bash
# Opens every Orbital screen/widget on the testbed VM and saves a screenshot of each, then
# reports warnings/errors the shell logged for the plugins. Run after scripts/e2e-testbed.sh.
#   scripts/e2e-screens.sh [outdir]
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# The VM harness lives in a separate repository; point TESTBED at its scripts/tb.
TB="${TESTBED:-$HOME/.local/share/omarchy-testbed}/scripts/tb"
[[ -x $TB ]] || { echo "Set TESTBED to an omarchy-testbed checkout (expected $TB to be executable)." >&2; exit 1; }
OUT="${1:-$REPO/test-output}"; mkdir -p "$OUT"; rm -f "$OUT"/*.png
E='export OMARCHY_PATH=/usr/share/omarchy XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr | head -1)'
vm() { "$TB" ssh "$E; $*"; }
n=0; results=()

# screen <name> <open-command> [<expected hyprctl layer namespace>]
screen() {
  local name="$1" cmd="$2" layer="${3:-}" file
  n=$((n+1)); printf -v file "%s/%02d-%s.png" "$OUT" "$n" "$name"
  vm "$cmd" >/dev/null 2>&1; sleep 3
  local seen="-"; [[ -n $layer ]] && seen="$(vm "hyprctl layers | grep -c 'namespace: $layer'" 2>/dev/null | tr -d '[:space:]')"
  "$TB" shot "$file" >/dev/null
  if [[ -n $layer && ${seen:-0} == 0 ]]; then results+=("FAIL  $name (layer $layer not on screen)"); else results+=("ok    $name"); fi
  "$TB" key esc >/dev/null 2>&1; sleep 1
}

vm "hyprctl eval 'hl.monitor({ output = \"\", mode = \"1366x768@60\", position = \"auto\", scale = 1 })'; hyprctl dispatch 'hl.dsp.focus({ workspace = \"9\" })'" >/dev/null 2>&1
vm "omarchy-notification-dismiss-all 2>/dev/null; true" >/dev/null 2>&1

screen desktop      "true"
screen launcher     "omarchy-shell shell toggle orbital.launcher '{}'" orbital-launcher
screen account      "omarchy-shell shell toggle orbital.account '{}'" orbital-account
screen appearance   "omarchy-shell shell toggle orbital.appearance '{}'" orbital-appearance
screen worldclock   "omarchy-shell shell toggle orbital.worldclock '{}'" orbital-worldclock
screen calendar     "omarchy-shell shell toggle orbital.clock '{}'" omarchy-keyboard-panel
screen keyboard     "omarchy-shell shell toggle orbital.keyboard '{}'" omarchy-keyboard-panel
PAYLOAD='{"pid":"4242","comm":"demo-app","exe":"/usr/bin/demo-app","signal":"SIGSEGV","title":"Process crashed","dismiss":"Dismiss","diagnose":"Diagnose with AI","rows":[{"label":"Process","value":"demo-app (PID 4242)"},{"label":"Binary","value":"/usr/bin/demo-app"},{"label":"Signal","value":"Segmentation fault (SIGSEGV)","crash":true}]}'
screen crash        "omarchy-shell shell summon orbital.crash '$PAYLOAD'" orbital-crash
vm "omarchy-shell shell call orbital.crash close ''" >/dev/null 2>&1
screen notification "notify-send 'Orbital' 'A themed notification toast' -t 6000"
# accent picker end to end: pink, screenshot, back to blue
vm "python3 ~/.config/omarchy/plugins/orbital.appearance/orbital-accent.py pink" >/dev/null 2>&1; sleep 8
screen accent-pink  "omarchy-shell shell toggle orbital.launcher '{}'" orbital-launcher
vm "python3 ~/.config/omarchy/plugins/orbital.appearance/orbital-accent.py blue" >/dev/null 2>&1; sleep 6

echo; echo "== screens (screenshots in $OUT)"; printf '%s\n' "${results[@]}"
echo; echo "== plugin warnings/errors from the shell log"
vm "journalctl --user -t omarchy-shell -b --no-pager | grep -iE 'orbital' | grep -iE 'WARN|ERR|fail|TypeError|ReferenceError' | grep -v DEBUG | sed -E 's/^.*omarchy-shell\\[[0-9]+\\]: *//' | cut -c1-200 | sort | uniq -c | sort -rn | head -15" || true
vm "hyprctl configerrors | head -5; omarchy plugin list | grep -c 'orbital.*enabled'"
! printf '%s\n' "${results[@]}" | grep -q '^FAIL'
