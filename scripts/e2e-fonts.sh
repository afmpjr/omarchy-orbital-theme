#!/usr/bin/env bash
# Opens the same Orbital screens under several monospace fonts on the testbed VM (1366x768 @1, the tightest
# case) and saves one screenshot per font and screen, plus a side-by-side montage per screen.
#   TESTBED=/path/to/omarchy-testbed scripts/e2e-fonts.sh [outdir]
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TB="${TESTBED:-$HOME/.local/share/omarchy-testbed}/scripts/tb"
[[ -x $TB ]] || { echo "Set TESTBED to an omarchy-testbed checkout (expected $TB)." >&2; exit 1; }
OUT="${1:-$REPO/test-output/fonts}"; mkdir -p "$OUT"; rm -f "$OUT"/*.png
E='export OMARCHY_PATH=/usr/share/omarchy XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr | head -1)'
vm() { "$TB" ssh "$E; $*"; }

# label|font family (as fontconfig names it)
FONTS=("jetbrains|JetBrainsMono Nerd Font" "cascadia|CaskaydiaMono Nerd Font" "meslo-lgl|MesloLGL Nerd Font"
       "meslo-lgs|MesloLGS Nerd Font" "iosevka|Iosevka Nerd Font Mono" "firacode|FiraCode Nerd Font")

echo "== installing the fonts in the VM"
vm "sudo pacman -S --noconfirm --needed ttf-cascadia-mono-nerd ttf-meslo-nerd ttf-iosevka-nerd ttf-firacode-nerd >/tmp/fonts-install.log 2>&1; tail -2 /tmp/fonts-install.log; fc-list : family | grep -ciE 'Caskaydia|Meslo|Iosevka|FiraCode'"
vm "hyprctl eval 'hl.monitor({ output = \"\", mode = \"1366x768@60\", position = \"auto\", scale = 1 })' >/dev/null; hyprctl dispatch 'hl.dsp.focus({ workspace = \"1\" })' >/dev/null; omarchy notification dismiss 'Setup Wi-Fi' >/dev/null 2>&1; omarchy notification dismiss 'Learn Keybindings' >/dev/null 2>&1; hyprctl eval 'hl.config({ cursor = { inactive_timeout = 1 } })' >/dev/null; hyprctl dispatch 'hl.dsp.cursor.move({ x = 1270, y = 20 })' >/dev/null" >/dev/null 2>&1

screen() { # <label> <screen> <ipc target> <layer>
  local label=$1 name=$2 target=$3 layer=$4
  vm "for i in 1 2 3; do hyprctl layers | grep -q '$layer' && break; omarchy-shell shell toggle $target '{}' >/dev/null; sleep 3; done" >/dev/null 2>&1
  sleep 1; "$TB" shot "$OUT/$name-$label.png" >/dev/null
  vm "omarchy-shell shell toggle $target '{}' >/dev/null 2>&1; sleep 1" >/dev/null 2>&1
}

for entry in "${FONTS[@]}"; do
  label=${entry%%|*}; fam=${entry#*|}
  echo "== $fam"
  vm "omarchy font set '$fam' >/dev/null 2>&1; sleep 3; omarchy restart shell >/dev/null 2>&1; sleep 9; echo \"active: \$(omarchy font current) / fc-match: \$(fc-match monospace family)\"" 2>&1 | tail -1
  screen "$label" launcher   orbital.launcher   orbital-launcher
  screen "$label" keyboard   orbital.keyboard   omarchy-keyboard-panel
  screen "$label" account    orbital.account    orbital-account
  screen "$label" worldclock orbital.worldclock orbital-worldclock
  screen "$label" calendar   orbital.clock      omarchy-keyboard-panel
done
vm "omarchy font set 'JetBrainsMono Nerd Font' >/dev/null 2>&1" >/dev/null 2>&1   # leave the VM as found

for name in launcher keyboard account worldclock calendar; do
  files=(); for entry in "${FONTS[@]}"; do files+=("$OUT/$name-${entry%%|*}.png"); done
  magick montage -label '%f' "${files[@]}" -tile 3x2 -geometry 683x384+4+4 -background '#222' -fill white "$OUT/montage-$name.png" 2>/dev/null
done
echo "done: $OUT"
