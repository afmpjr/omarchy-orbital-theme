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
readme_says "omarchy theme set orbital"
"$TB" ssh "$ENVSET; omarchy theme set orbital" 2>&1 | tail -2
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
ok "published repo is complete (docs, license, executable installer, $N wallpapers)"

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
# The README promises a bar with widgets in it: check the state the user will actually see, not
# just that the plugin folders exist.
BAR="$("$TB" ssh "$ENVSET; jq -r .bar.id ~/.config/omarchy/shell.json")"
[[ $BAR == orbital.floating-bar ]] || bad "the theme bar is not the one in use (bar.id=$BAR)"
# No double quotes inside the ssh string: they would close it. One id per line, joined here.
LEFT="$("$TB" ssh "$ENVSET; jq -r '.bar.layout.left[].id' ~/.config/omarchy/shell.json" | tr '\n' ' ')"
RIGHT="$("$TB" ssh "$ENVSET; jq -r '.bar.layout.right[].id' ~/.config/omarchy/shell.json" | tr '\n' ' ')"
grep -qw orbital.dock <<<"$LEFT" || bad "the dock is not on the left of the bar (left: $LEFT)"
for w in orbital.keyboard orbital.divider orbital.clock; do
  grep -qw "$w" <<<"$RIGHT" || bad "$w is not on the right of the bar (right: $RIGHT)"
done
ok "bar.id=$BAR, dock on the left, keyboard/divider/clock on the right"
BARGEOM="$("$TB" ssh "$ENVSET; hyprctl layers | grep -m1 'namespace: omarchy-bar'" | tr -d '\r')"
echo "info - bar layer: $(grep -oE 'xywh: [0-9 ]+' <<<"$BARGEOM" || echo unknown) (floating = a gap off the edge)"

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

# All or nothing, on the real system: a failure in the middle has to put back exactly what was
# there. Here there IS a working install, so the rollback must restore it, not delete it.
SJ_BEFORE="$("$TB" ssh "$ENVSET; md5sum < ~/.config/omarchy/shell.json" | cut -d' ' -f1)"
ROLL="$("$TB" ssh "$ENVSET; cd $GT && ORBITAL_FAIL_AT=widgets ./install.sh --bar-widgets --no-restart" 2>&1)" && bad "the installer said it succeeded even though a step was forced to fail" || true
grep -qi 'nothing was applied' <<<"$ROLL" || bad "a failed install did not say that nothing was applied"
SJ_AFTER="$("$TB" ssh "$ENVSET; md5sum < ~/.config/omarchy/shell.json" | cut -d' ' -f1)"
[[ $SJ_BEFORE == "$SJ_AFTER" ]] || bad "a failed re-install changed shell.json ($SJ_BEFORE -> $SJ_AFTER)"
"$TB" ssh "$ENVSET; omarchy plugin list" | grep -qE '^orbital[.]dock +enabled' || bad "a failed re-install left the plugins disabled"
"$TB" ssh "$ENVSET; grep -c 'hypr.orbital' ~/.config/hypr/hyprland.lua" >/dev/null || bad "a failed re-install broke the Hyprland hook"
ok "a failed re-install rolls back to the installed state instead of breaking it"

# Screenshot: best effort. The guest keeps its native 1280x800 (this Hyprland's `hyprctl dispatch`
# is the Lua form, so the classic `workspace 9` is a syntax error there and resizing is not worth
# fighting for a test artifact); a missing launcher in the picture must not fail the run.
for i in 1 2 3 4; do
  "$TB" ssh "$ENVSET; hyprctl layers" 2>/dev/null | grep -q orbital-launcher && break
  "$TB" ssh "$ENVSET; omarchy-shell shell toggle orbital.launcher '{}'" >/dev/null 2>&1 || true
  sleep 3
done
sleep 3
if "$TB" shot "$OUT" >/dev/null 2>&1; then echo "screenshot: $OUT"; else echo "warn - could not take the screenshot"; fi
echo "FRESH INSTALL OK"
