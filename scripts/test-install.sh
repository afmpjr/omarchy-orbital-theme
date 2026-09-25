#!/usr/bin/env bash
# Sandbox test of install.sh + the accent picker: fake HOME, stubbed `omarchy`.
# Verifies files land where expected, the baseline is pristine blue, blue
# regenerates byte-identical, other colors actually change accent AND glass,
# and uninstall cleans up. Does not touch the real system.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
REAL_OMARCHY="$(command -v omarchy || true)"   # the real CLI, for plugin validate (the stub below replaces it on PATH)
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export ORBITAL_INSTALL_NO_WAIT=1 HOME="$T/home"; mkdir -p "$HOME/.config/hypr" "$T/bin" "$HOME/.config/omarchy/themes"
printf 'require("default.hypr.omarchy")\n' > "$HOME/.config/hypr/hyprland.lua"
cat > "$T/bin/omarchy" <<'STUB'
#!/usr/bin/env bash
# Minimal stand-in for the omarchy CLI: records calls, remembers enabled plugins, "installs" plugins.
echo "omarchy $*" >> "$HOME/omarchy-calls.log"
case "$1 $2" in
  "plugin enable") echo "$3" >> "$HOME/enabled.txt" ;;
  "plugin add") mkdir -p "$HOME/.config/omarchy/plugins/jankeesvw.notification-center"; echo jankeesvw.notification-center >> "$HOME/enabled.txt" ;;
  "plugin list") [[ -f $HOME/enabled.txt ]] && sort -u "$HOME/enabled.txt" | awk '{printf "%-32s enabled   stub\n", $1}' ;;
esac
exit 0
STUB
# Everything that could touch the REAL session is stubbed: this test must never restart, kill or
# reload anything on the machine that runs it (an earlier version killed the user's shell).
for c in omarchy-shell quickshell hyprctl systemctl xdg-settings; do
  printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/$c"
done
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/omarchy-shell"
chmod +x "$T/bin/"*; export PATH="$T/bin:$PATH"
for c in quickshell hyprctl systemctl; do [[ $(command -v $c) == "$T/bin/$c" ]] || { echo "sandbox failed to stub $c"; exit 1; }; done
ok() { echo "ok   - $1"; }; bad() { echo "FAIL - $1"; exit 1; }

# Theme as `omarchy theme install` would leave it (clone in themes/orbital).
cp -r "$REPO" "$HOME/.config/omarchy/themes/orbital"; rm -rf "$HOME/.config/omarchy/themes/orbital/.git"

mkdir -p "$HOME/.config/omarchy" "$HOME/.local/share/applications"
cp /usr/share/omarchy/config/omarchy/shell.json "$HOME/.config/omarchy/shell.json"
printf 'require("default.hypr.toggles")\n' >> "$HOME/.config/hypr/hyprland.lua"
# Omarchy's stock input.lua: kb_layout/kb_options only in comments (a grep with no match must not abort the installer)
printf -- '-- hl.config({ input = { kb_layout = "us" } })\nhl.config({ input = { repeat_rate = 40 } })\n' > "$HOME/.config/hypr/input.lua"
touch "$HOME/.local/share/applications/com.mitchellh.ghostty.desktop"
mkdir -p "$HOME/.config/ghostty"; printf 'font-size = 9\n' > "$HOME/.config/ghostty/config"
"$REPO/install.sh" --full --no-restart >/dev/null
GC="$HOME/.config/ghostty/config"
[[ $(grep -c 'ctrl+enter=unbind' "$GC") == 1 ]] || bad "ghostty ctrl+enter not freed"; ok "Ghostty: Ctrl+Enter freed"
SJ="$HOME/.config/omarchy/shell.json"
[[ $(jq -r .bar.id "$SJ") == orbital.floating-bar && $(jq -r .bar.floatGapScale "$SJ") == 0.5 && $(jq -r .bar.cornerRadius "$SJ") == 10 ]] || bad "bar config"
[[ $(jq -c '[.bar.layout.left[].id, .bar.layout.center[].id]' "$SJ") == '["orbital.dock","orbital.workspaces"]' ]] || bad "layout left/center"
[[ $(jq -r '.bar.layout.right[-1].id' "$SJ") == jankeesvw.notification-center && $(jq -r '.bar.layout.right[-2].id' "$SJ") == orbital.clock && $(jq -r '.bar.layout.right[-3].id' "$SJ") == orbital.divider ]] || bad "layout right (bell, clock, divider order)"
jq -e '.bar.layout.right | map(.id) | index("omarchy.tray") == 0 and (index("omarchy.indicators") == 1)' "$SJ" >/dev/null || bad "tray/indicators order"
[[ $(jq -r '.bar.layout.right[-2].formatAlt' "$SJ") == "d MMMM 'W'ww yyyy" ]] || bad "clock format"
ok "full: bar config + layout"
[[ $(stat -c %a "$SJ") == 644 ]] || bad "shell.json permissions"; ok "shell.json keeps 644"
[[ $(jq -c '[.bar.layout.right[].id | select(. == "jankeesvw.notification-center")] | length' "$SJ") == 1 ]] || bad "bell missing/duplicated"; ok "notification center installed and placed last"
ls "$HOME/.config/omarchy/shell.json.bak-orbital-"* >/dev/null || bad "shell.json backup"; ok "shell.json backed up"
G="$(grep -n 'hypr.orbital-gaps' "$HOME/.config/hypr/hyprland.lua" | cut -d: -f1)"; TG="$(grep -n 'default.hypr.toggles' "$HOME/.config/hypr/hyprland.lua" | cut -d: -f1)"
(( G < TG )) || bad "gaps must load before toggles"; ok "gaps load before the gaps toggle"
grep -q "orbital-bindings" "$HOME/.config/hypr/hyprland.lua" || bad "bindings hook"; ok "launcher binding hooked"
jq -e '.pinned | map(.entry) | index("com.mitchellh.ghostty")' "$HOME/.local/state/omarchy/orbital-dock.json" >/dev/null || bad "dock pins"; ok "default dock pins from installed apps"
"$REPO/install.sh" --full --no-restart >/dev/null
[[ $(jq -c '.bar.layout.right | map(.id) | map(select(. == "orbital.clock")) | length' "$SJ") == 1 ]] || bad "full not idempotent"; ok "full is idempotent"
[[ $(grep -c 'ctrl+enter=unbind' "$GC") == 1 ]] || bad "ghostty block duplicated"; ok "Ghostty fix idempotent"
[[ $(jq -r '.bar.layout.right[-4].id' "$SJ") == orbital.keyboard ]] || bad "keyboard widget not in layout"; ok "keyboard widget placed before divider + clock + bell"
[[ ! -f $HOME/.config/hypr/orbital-keyboard.lua ]] || bad "keyboard file written with a single layout"; ok "single layout: no keyboard config forced"
"$REPO/install.sh" --full --no-restart --keyboard-layouts br,us >/dev/null
KB="$HOME/.config/hypr/orbital-keyboard.lua"
grep -q 'kb_layout = "br,us"' "$KB" && grep -q 'Shift_L", next_layout, { release = true }' "$KB" && grep -q 'Alt_L", next_layout' "$KB" || bad "keyboard config"
! grep -q 'grp:' "$KB" || bad "grp: option must not be set (it would double-toggle)"; ok "Alt+Shift release binds configured for br,us (no grp: option)"
[[ $(grep -c 'hypr.orbital-keyboard' "$HOME/.config/hypr/hyprland.lua") == 1 ]] || bad "keyboard hook twice"
"$REPO/install.sh" --full --no-restart --keyboard-layouts br,us >/dev/null
[[ $(grep -c 'hypr.orbital-keyboard' "$HOME/.config/hypr/hyprland.lua") == 1 ]] || bad "keyboard hook not idempotent"; ok "keyboard hook idempotent"
for id in orbital.launcher orbital.dock orbital.account orbital.appearance orbital.worldclock orbital.crash orbital.ui orbital.clock orbital.workspaces orbital.divider orbital.floating-bar orbital.bar; do
  [[ -d $HOME/.config/omarchy/plugins/$id ]] || bad "plugin $id missing"
done; ok "plugins installed (both bars present, only .bar.id is ever loaded)"
# The schema is Omarchy's, not ours: ask the real CLI, so a manifest that this Omarchy would
# reject cannot ship. orbital.ui is a shared library and deliberately has no manifest.
if [[ -n $REAL_OMARCHY ]]; then
  for d in "$REPO"/plugins/*/; do
    id="$(basename "$d")"
    if [[ -f $d/manifest.json ]]; then
      OMARCHY_PATH=/usr/share/omarchy "$REAL_OMARCHY" plugin validate "$d" >/dev/null 2>&1 || bad "omarchy plugin validate rejected $id"
    else
      [[ $id == orbital.ui ]] || bad "$id has no manifest.json"
    fi
  done
  ok "every manifest passes 'omarchy plugin validate'"
else
  echo "skip - 'omarchy plugin validate' (no omarchy on PATH)"
fi
grep -q 'require("hypr.orbital")' "$HOME/.config/hypr/hyprland.lua" && [[ -f $HOME/.config/hypr/orbital.lua ]] || bad "hyprland hook"; ok "hyprland hook"
"$REPO/install.sh" --no-restart >/dev/null
[[ $(grep -c 'require("hypr.orbital")' "$HOME/.config/hypr/hyprland.lua") == 1 ]] || bad "hook not idempotent"; ok "idempotent hook"
[[ $(jq -r '.bar.layout.right[-2].id' "$HOME/.config/omarchy/shell.json") == orbital.clock ]] || bad "--full layout was disturbed by widget placement"
# The generated keyboard file can disappear (hand-deleted, or a dotfiles sync that drops it) while
# its require stays: that is a hard Hyprland error. The installer must drop the dangling require.
rm -f "$HOME/.config/hypr/orbital-keyboard.lua"
printf 'require("hypr.orbital-keyboard") -- orbital\n' >> "$HOME/.config/hypr/hyprland.lua"
[[ -n $(grep -c 'hypr.orbital-keyboard' "$HOME/.config/hypr/hyprland.lua") ]] || bad "test setup: dangling require not created"
"$REPO/install.sh" --no-restart >/dev/null
! grep -q 'hypr.orbital-keyboard' "$HOME/.config/hypr/hyprland.lua" || bad "dangling require kept: Hyprland would fail to load the config"
grep -q 'require("hypr.orbital")' "$HOME/.config/hypr/hyprland.lua" || bad "reconcile dropped a require that has its file"
ok "dangling require removed, valid ones kept"
! grep -q "plugin enable orbital.clock --section" "$HOME/omarchy-calls.log" || bad "--full must not re-place widgets"; ok "--full keeps its layout (no widget re-placement)"
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
! grep -q 'orbital-shortcuts' "$GC" || bad "ghostty block not removed"; ok "uninstall removes the Ghostty block"
[[ ! -d $HOME/.config/omarchy/plugins/orbital.dock && ! -d $HOME/.config/omarchy/plugins/orbital.bar && ! -d $HOME/.config/omarchy/plugins/orbital.floating-bar && ! -f $HOME/.config/hypr/orbital.lua ]] || bad "uninstall"
! grep -q 'hypr.orbital' "$HOME/.config/hypr/hyprland.lua" || bad "hook not removed"; ok "uninstall clean"
echo "ALL PASSED"
