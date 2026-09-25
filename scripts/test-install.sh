#!/usr/bin/env bash
# Sandbox test of install.sh + the accent picker: fake HOME, stubbed `omarchy`.
# Verifies files land where expected, the baseline is pristine blue, blue
# regenerates byte-identical, other colors actually change accent AND glass,
# and uninstall cleans up. Does not touch the real system.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export ORBITAL_INSTALL_NO_WAIT=1 HOME="$T/home"; mkdir -p "$HOME/.config/hypr" "$T/bin" "$HOME/.config/omarchy/themes"
printf 'require("default.hypr.omarchy")\n' > "$HOME/.config/hypr/hyprland.lua"
cat > "$T/bin/omarchy" <<'STUB'
#!/usr/bin/env bash
echo "omarchy $*" >> "$HOME/omarchy-calls.log"
STUB
chmod +x "$T/bin/omarchy"; export PATH="$T/bin:$PATH"
ok() { echo "ok   - $1"; }; bad() { echo "FAIL - $1"; exit 1; }

# Theme as `omarchy theme install` would leave it (clone in themes/orbital).
cp -r "$REPO" "$HOME/.config/omarchy/themes/orbital"; rm -rf "$HOME/.config/omarchy/themes/orbital/.git"

mkdir -p "$HOME/.config/omarchy" "$HOME/.local/share/applications"
cp /usr/share/omarchy/config/omarchy/shell.json "$HOME/.config/omarchy/shell.json"
printf 'require("default.hypr.toggles")\n' >> "$HOME/.config/hypr/hyprland.lua"
touch "$HOME/.local/share/applications/com.mitchellh.ghostty.desktop"
"$REPO/install.sh" --full --no-restart >/dev/null
SJ="$HOME/.config/omarchy/shell.json"
[[ $(jq -r .bar.id "$SJ") == orbital.floating-bar && $(jq -r .bar.floatGapScale "$SJ") == 0.5 && $(jq -r .bar.cornerRadius "$SJ") == 10 ]] || bad "bar config"
[[ $(jq -c '[.bar.layout.left[].id, .bar.layout.center[].id]' "$SJ") == '["orbital.dock","orbital.workspaces"]' ]] || bad "layout left/center"
[[ $(jq -r '.bar.layout.right[-1].id' "$SJ") == orbital.clock && $(jq -r '.bar.layout.right[-2].id' "$SJ") == orbital.divider ]] || bad "layout right"
jq -e '.bar.layout.right | map(.id) | index("omarchy.tray") == 0 and (index("omarchy.indicators") == 1)' "$SJ" >/dev/null || bad "tray/indicators order"
[[ $(jq -r '.bar.layout.right[-1].formatAlt' "$SJ") == "d MMMM 'W'ww yyyy" ]] || bad "clock format"
ok "full: bar config + layout"
[[ $(stat -c %a "$SJ") == 644 ]] || bad "shell.json permissions"; ok "shell.json keeps 644"
ls "$HOME/.config/omarchy/shell.json.bak-orbital-"* >/dev/null || bad "shell.json backup"; ok "shell.json backed up"
G="$(grep -n 'hypr.orbital-gaps' "$HOME/.config/hypr/hyprland.lua" | cut -d: -f1)"; TG="$(grep -n 'default.hypr.toggles' "$HOME/.config/hypr/hyprland.lua" | cut -d: -f1)"
(( G < TG )) || bad "gaps must load before toggles"; ok "gaps load before the gaps toggle"
grep -q "orbital-bindings" "$HOME/.config/hypr/hyprland.lua" || bad "bindings hook"; ok "launcher binding hooked"
jq -e '.pinned | map(.entry) | index("com.mitchellh.ghostty")' "$HOME/.local/state/omarchy/orbital-dock.json" >/dev/null || bad "dock pins"; ok "default dock pins from installed apps"
"$REPO/install.sh" --full --no-restart >/dev/null
[[ $(jq -c '.bar.layout.right | map(.id) | map(select(. == "orbital.clock")) | length' "$SJ") == 1 ]] || bad "full not idempotent"; ok "full is idempotent"
[[ $(jq -r '.bar.layout.right[-3].id' "$SJ") == orbital.keyboard ]] || bad "keyboard widget not in layout"; ok "keyboard widget placed before divider + clock"
[[ ! -f $HOME/.config/hypr/orbital-keyboard.lua ]] || bad "keyboard file written with a single layout"; ok "single layout: no keyboard config forced"
"$REPO/install.sh" --full --no-restart --keyboard-layouts br,us >/dev/null
KB="$HOME/.config/hypr/orbital-keyboard.lua"
grep -q 'kb_layout = "br,us"' "$KB" && grep -q 'grp:alt_shift_toggle' "$KB" || bad "keyboard config"; ok "Alt+Shift toggle configured for br,us"
[[ $(grep -c 'hypr.orbital-keyboard' "$HOME/.config/hypr/hyprland.lua") == 1 ]] || bad "keyboard hook twice"
"$REPO/install.sh" --full --no-restart --keyboard-layouts br,us >/dev/null
[[ $(grep -c 'hypr.orbital-keyboard' "$HOME/.config/hypr/hyprland.lua") == 1 ]] || bad "keyboard hook not idempotent"; ok "keyboard hook idempotent"
for id in orbital.launcher orbital.dock orbital.account orbital.appearance orbital.worldclock orbital.crash orbital.ui orbital.clock orbital.workspaces orbital.divider; do
  [[ -d $HOME/.config/omarchy/plugins/$id ]] || bad "plugin $id missing"
done; ok "plugins installed"
grep -q 'require("hypr.orbital")' "$HOME/.config/hypr/hyprland.lua" && [[ -f $HOME/.config/hypr/orbital.lua ]] || bad "hyprland hook"; ok "hyprland hook"
"$REPO/install.sh" --no-restart >/dev/null
[[ $(grep -c 'require("hypr.orbital")' "$HOME/.config/hypr/hyprland.lua") == 1 ]] || bad "hook not idempotent"; ok "idempotent hook"
grep -q "plugin enable orbital.dock --section left" "$HOME/omarchy-calls.log" || bad "dock not placed"; ok "bar widgets placed via CLI"
[[ -f $HOME/.local/state/omarchy/orbital-accent-base/colors.toml ]] || bad "baseline"
grep -q '^accent = "#39A9FF"' "$HOME/.local/state/omarchy/orbital-accent-base/colors.toml" || bad "baseline not blue"; ok "pristine blue baseline"

ACC="$HOME/.config/omarchy/plugins/orbital.appearance/orbital-accent.py"
T_DIR="$HOME/.config/omarchy/themes/orbital"
python3 "$ACC" purple; grep -q '^accent = "#9539FF"' "$T_DIR/colors.toml" || bad "purple accent"
[[ $(grep -m1 '^background' "$T_DIR/shell.toml") != *0A1422* ]] || bad "glass not recolored"; ok "purple recolors accent and glass"
grep -q '"border": "rgba(' "$HOME/.local/state/omarchy/orbital-accent.json" || bad "border state"; ok "border color state written"
python3 "$ACC" blue
diff -r -q "$HOME/.local/state/omarchy/orbital-accent-base" "$T_DIR" 2>&1 | grep -v "^Only in" && bad "blue not identical" || ok "blue regenerates identical"

rm -rf "$HOME/.local/state/omarchy/orbital-accent-base"
out="$(python3 "$ACC" red 2>&1 || true)"
[[ $out == *"pristine theme copy missing"* ]] && ok "missing baseline fails loudly" || bad "silent failure"
"$REPO/install.sh" --uninstall >/dev/null
[[ ! -d $HOME/.config/omarchy/plugins/orbital.dock && ! -f $HOME/.config/hypr/orbital.lua ]] || bad "uninstall"
! grep -q 'hypr.orbital' "$HOME/.config/hypr/hyprland.lua" || bad "hook not removed"; ok "uninstall clean"
echo "ALL PASSED"
