#!/usr/bin/env bash
# Sandbox test of install.sh + the accent picker: fake HOME, stubbed `omarchy`.
# Verifies files land where expected, the baseline is pristine blue, blue
# regenerates byte-identical, other colors actually change accent AND glass,
# and uninstall cleans up. Does not touch the real system.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME/.config/hypr" "$T/bin" "$HOME/.config/omarchy/themes"
printf 'require("default.hypr.omarchy")\n' > "$HOME/.config/hypr/hyprland.lua"
cat > "$T/bin/omarchy" <<'STUB'
#!/usr/bin/env bash
echo "omarchy $*" >> "$HOME/omarchy-calls.log"
STUB
chmod +x "$T/bin/omarchy"; export PATH="$T/bin:$PATH"
ok() { echo "ok   - $1"; }; bad() { echo "FAIL - $1"; exit 1; }

# Theme as `omarchy theme install` would leave it (clone in themes/orbital).
cp -r "$REPO" "$HOME/.config/omarchy/themes/orbital"; rm -rf "$HOME/.config/omarchy/themes/orbital/.git"

"$REPO/install.sh" --bar-widgets --no-restart >/dev/null
for id in orbital.launcher orbital.dock orbital.account orbital.appearance orbital.worldclock orbital.crash orbital.ui orbital.clock orbital.workspaces orbital.divider; do
  [[ -d $HOME/.config/omarchy/plugins/$id ]] || bad "plugin $id missing"
done; ok "plugins installed"
grep -q 'hypr.orbital' "$HOME/.config/hypr/hyprland.lua" && [[ -f $HOME/.config/hypr/orbital.lua ]] || bad "hyprland hook"; ok "hyprland hook"
"$REPO/install.sh" --no-restart >/dev/null
[[ $(grep -c 'hypr.orbital' "$HOME/.config/hypr/hyprland.lua") == 1 ]] || bad "hook not idempotent"; ok "idempotent hook"
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
