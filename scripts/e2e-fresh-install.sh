#!/usr/bin/env bash
# Fresh-install check on a clean Omarchy VM (project: omarchy-testbed).
#
# Follows the README "Install" block verbatim, from the PUBLIC GitHub URL instead of this working
# tree, so it also proves the published repo is complete (nothing important left uncommitted or
# gitignored) and that the documented path works on an account that has never seen the theme.
#   scripts/e2e-fresh-install.sh [out.png]
#
# For the --full variant and the bar/menu walkthrough, see scripts/e2e-testbed.sh.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# The VM harness lives in a separate repository; point TESTBED at its scripts/tb.
TB="${TESTBED:-$HOME/.local/share/omarchy-testbed}/scripts/tb"
[[ -x $TB ]] || { echo "Set TESTBED to an omarchy-testbed checkout (expected $TB to be executable)." >&2; exit 1; }
URL="${ORBITAL_REPO_URL:-https://github.com/afmpjr/omarchy-orbital-theme}"
OUT="${1:-/tmp/e2e-fresh.png}"
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; exit 1; }

# The script must not drift from the docs: every command it runs has to still be in the README.
readme_says() {
  grep -qF "$1" "$REPO/README.md" || { echo "FAIL: README no longer contains: $1"; exit 1; }
}

"$TB" reset; "$TB" up >/dev/null
echo -n "Waiting for the guest"; until "$TB" ssh true 2>/dev/null; do echo -n .; sleep 5; done; echo
until "$TB" ssh 'pgrep -x quickshell >/dev/null && pgrep -x Hyprland >/dev/null' 2>/dev/null; do sleep 3; done; sleep 8
ENVSET='export OMARCHY_PATH=/usr/share/omarchy XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr | head -1)'

# The account must start with nothing of Orbital in it, or this proves nothing. (Omarchy itself
# creates ~/.config/omarchy on first boot, so the check is for Orbital, not for an empty folder.)
PRE="$("$TB" ssh "$ENVSET; ls -1 ~/.config/omarchy/themes ~/.config/omarchy/plugins 2>/dev/null | grep -i orbital; cat ~/.local/state/omarchy/current/theme.name 2>/dev/null" | tr -d '\r' | tr '\n' ' ')"
[[ $PRE != *orbital* ]] || { echo "FAIL: this account already has Orbital in it: $PRE"; exit 1; }
ok "clean account: no Orbital theme, plugin or active theme (default was: $PRE)"

# ---- README "Install", verbatim ----
readme_says "omarchy theme install $URL"
"$TB" ssh "$ENVSET; omarchy theme install $URL" 2>&1 | tail -2
readme_says "./install.sh --bar-widgets"
"$TB" ssh "$ENVSET; cd ~/.config/omarchy/themes/orbital && ./install.sh --bar-widgets" 2>&1 | tail -12
readme_says "omarchy theme set Orbital"
"$TB" ssh "$ENVSET; omarchy theme set Orbital" 2>&1 | tail -2
sleep 8

GT='~/.config/omarchy/themes/orbital'   # single quotes: the tilde must be expanded by the guest, not here
# The clone has to be the published repo, whole and clean.
"$TB" ssh "$ENVSET; cd $GT && git rev-parse --short HEAD && git status --porcelain" > /tmp/e2e-fresh-git 2>&1
HEAD_SHA="$(head -1 /tmp/e2e-fresh-git)"; DIRTY="$(tail -n +2 /tmp/e2e-fresh-git | tr -d '[:space:]')"
[[ -n $HEAD_SHA && $HEAD_SHA != fatal* ]] || bad "theme dir is not a git clone of $URL"
[[ -z $DIRTY ]] || bad "published repo has uncommitted/missing files: $DIRTY"
ok "cloned from the public URL at $HEAD_SHA, working tree clean"
for f in CREDITS.md LICENSE README.md install.sh .omarchy-theme.yml; do
  "$TB" ssh "$ENVSET; test -f $GT/$f" || bad "$f missing from the published repo"
done
"$TB" ssh "$ENVSET; test -x $GT/install.sh" || bad "install.sh lost its exec bit in the clone"
N="$("$TB" ssh "$ENVSET; ls -1 $GT/backgrounds | wc -l")"
[[ $N == 6 ]] || bad "expected 6 wallpapers in the published repo, found $N"
ok "published repo is complete (docs, license, executable installer, 7 wallpapers)"

# Theme applied.
THEME="$("$TB" ssh "$ENVSET; cat ~/.local/state/omarchy/current/theme.name")"
[[ $THEME == orbital ]] || bad "theme not applied (current=$THEME)"
ok "theme applied: $THEME"

# Every plugin the README promises, installed and enabled.
LIST="$("$TB" ssh "$ENVSET; omarchy plugin list")"
for id in orbital.launcher orbital.account orbital.appearance orbital.worldclock orbital.crash \
          orbital.dock orbital.workspaces orbital.keyboard orbital.clock orbital.divider \
          orbital.floating-bar orbital.bar orbital.ui; do
  "$TB" ssh "$ENVSET; test -d ~/.config/omarchy/plugins/$id" || bad "plugin $id not installed"
done
ok "all 13 plugin folders installed"
for id in orbital.launcher orbital.account orbital.appearance orbital.worldclock orbital.crash \
          orbital.dock orbital.workspaces orbital.keyboard orbital.clock orbital.divider orbital.floating-bar; do
  grep -qE "^$id +enabled" <<<"$LIST" || bad "$id is installed but not enabled"
done
grep -qE '^orbital\.bar +disabled' <<<"$LIST" || bad "the unused bar alternative should stay disabled"
ok "every promised plugin enabled; only the unused bar alternative disabled"
BAR="$("$TB" ssh "$ENVSET; jq -r .bar.id ~/.config/omarchy/shell.json")"
echo "info - bar.id after the README path: $BAR"

# Hyprland part: hook present, no dangling require, no config error.
"$TB" ssh "$ENVSET; grep -q 'require(\"hypr.orbital\")' ~/.config/hypr/hyprland.lua && test -f ~/.config/hypr/orbital.lua" \
  || bad "Hyprland hook missing (line or file)"
DANGLE=""
for m in $("$TB" ssh "$ENVSET; grep -oE 'hypr[.]orbital-[a-z-]+' ~/.config/hypr/hyprland.lua | sort -u" | tr -d '\r'); do
  "$TB" ssh "$ENVSET; test -f ~/.config/hypr/$m.lua" || DANGLE="$DANGLE $m"
done
[[ -z $DANGLE ]] || bad "dangling require(s) with no file:$DANGLE"
ok "Hyprland hook present, no require without a file"
ERRS="$("$TB" ssh "$ENVSET; hyprctl configerrors | head -3" | tr -d '\r')"
[[ -z ${ERRS//[[:space:]]/} ]] || bad "hyprland config errors: $ERRS"
ok "hyprctl configerrors is empty"

# Schema is Omarchy's: let the real CLI judge every manifest.
INVALID=""
for d in $("$TB" ssh "$ENVSET; ls -d ~/.config/omarchy/plugins/orbital.*/" | tr -d '\r'); do
  "$TB" ssh "$ENVSET; test -f $d/manifest.json" || continue
  "$TB" ssh "$ENVSET; omarchy plugin validate $d" >/dev/null 2>&1 || INVALID="$INVALID $d"
done
[[ -z $INVALID ]] || bad "this Omarchy rejects:$INVALID"
ok "every installed manifest passes 'omarchy plugin validate'"

# Viewport for the screenshot: plain hyprctl forms, because a payload with escaped quotes inside a
# quoted ssh argument trips bash when the whole command sits in a command substitution.
"$TB" ssh "$ENVSET; hyprctl keyword monitor ,1366x768@60,auto,1" >/dev/null
"$TB" ssh "$ENVSET; hyprctl dispatch workspace 9" >/dev/null
for i in 1 2 3 4; do "$TB" ssh "$ENVSET; hyprctl layers" 2>/dev/null | grep -q orbital-launcher && break; "$TB" ssh "$ENVSET; omarchy-shell shell toggle orbital.launcher '{}'" >/dev/null 2>&1; sleep 3; done
sleep 4; "$TB" shot "$OUT" >/dev/null
echo "screenshot: $OUT"
echo "FRESH INSTALL OK"
