#!/usr/bin/env bash
# Orbital installer: theme companions that `omarchy theme install` cannot ship.
#
#   omarchy theme install https://github.com/afmpjr/omarchy-orbital-theme   # the theme itself
#   ./install.sh [--full] [--keyboard-layouts us,br] [--bar-widgets] [--no-restart] [--dry-run]      # plugins + Hyprland glass
#   ./install.sh --uninstall
#
#   --full  also reproduces the author's desktop: Orbital floating bar (bottom, half-size gap),
#           dock left / workspaces center / divider + clock right, Super+S launcher binding,
#           4-finger touchpad swipe switches workspaces (--no-gestures skips it),
#           frees Ctrl+Enter in Ghostty (--fix-terminal-shortcuts does only that), 8/12 window gaps, text size 10, keyboard layout widget + Alt+Shift and default dock pins. Your shell.json is backed up first.
#
# Both bar plugins are copied (orbital.floating-bar, the default, and orbital.bar, the self-contained
# alternative), but only the one named in shell.json's .bar.id is ever loaded.
#
# All or nothing. Every problem that can be found without touching the system is found first and
# reported together; anything that goes wrong while applying is rolled back to the exact previous
# state and reported. The shell is only restarted, and the install only declared done, after a
# verification pass reads the real state back and finds every promised plugin enabled and placed.
#
# Idempotent. Never edits shell.json by hand (uses `omarchy plugin enable`),
# backs up anything it replaces OUTSIDE the plugins folder (the shell scans it).
set -euo pipefail

export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$HOME/.config"
PLUGINS="$CFG/omarchy/plugins"
BACKUPS="$CFG/omarchy/plugin-backups"
BASE="$HOME/.local/state/omarchy/orbital-accent-base"
HYPR="$CFG/hypr"
DROPIN="$CFG/systemd/user/omarchy-crash-watch.service.d"
SJ="$CFG/omarchy/shell.json"
MARK='require("hypr.orbital") -- orbital'
STAMP="$(date +%Y%m%dT%H%M%S)"

OVERLAYS=(orbital.launcher orbital.account orbital.appearance orbital.worldclock orbital.crash)
LIBS=(orbital.ui)
WIDGETS=("orbital.dock:left" "orbital.workspaces:center" "orbital.keyboard:right" "orbital.clock:right")
EXTRA_WIDGETS=(orbital.divider)
BAR_IDS=(orbital.floating-bar orbital.bar)

DRY=0 RESTART=1 BAR=0 UNINSTALL=0 FULL=0 KBLAYOUTS= LAUNCHER_KEY=1 ALT_SHIFT=1 GESTURES=1 TERM_FIX=0
while (( $# )); do
  a=$1; shift
  case $a in
    --dry-run) DRY=1 ;; --no-restart) RESTART=0 ;; --bar-widgets) BAR=1 ;; --full) FULL=1; BAR=1 ;;
    --no-launcher-key) LAUNCHER_KEY=0 ;; --no-alt-shift) ALT_SHIFT=0 ;; --no-gestures) GESTURES=0 ;; --fix-terminal-shortcuts) TERM_FIX=1 ;;
    --keyboard-layouts) KBLAYOUTS="${1:?--keyboard-layouts needs a list, e.g. us,br}"; shift ;; --uninstall) UNINSTALL=1 ;;
    # The header comment is the help text: print the block of '#' lines under the shebang.
    -h|--help) awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say() { echo "==> $*"; }
nap() { [[ ${ORBITAL_INSTALL_NO_WAIT:-} == 1 ]] || sleep "$1"; }  # tests skip the waits
run() { if (( DRY )); then echo "    [dry-run] $*"; else "$@"; fi; }
have_omarchy() { command -v omarchy >/dev/null 2>&1; }
problem() { PROBLEMS+=("$1"); echo "    ! $1" >&2; }
warn() { WARNINGS+=("$1"); }

# ---------------------------------------------------------------------------------------------
# Transaction: snapshot what we are about to change, and put it back if anything fails.
# ORBITAL_FAIL_AT is a test hook (scripts/test-install.sh) that fails one named step on purpose.
# ---------------------------------------------------------------------------------------------
PROBLEMS=(); WARNINGS=(); UNDO=(); TOUCHED_SHELL_JSON=0; DONE=0
SNAP=""
trip() { [[ ${ORBITAL_FAIL_AT:-} == "$1" ]]; }

ensure_dir() { # mkdir -p, remembering whether we were the ones who created it
  local d=$1
  if (( DRY )); then echo "    [dry-run] mkdir -p $d"; return 0; fi
  [[ -d $d ]] && return 0
  snapshot "$d"
  mkdir -p "$d"
}
snapshot() { # remember <path>: enough to restore it byte for byte, including "it did not exist"
  local f=$1
  (( DRY )) && return 0
  if [[ -e $f ]]; then mkdir -p "$SNAP$(dirname "$f")"; cp -a "$f" "$SNAP$f"
  else mkdir -p "$SNAP$(dirname "$f")"; : > "$SNAP$f.absent"; fi
  UNDO+=("$f")
}
rollback() { # newest first; every step is best effort, and every failure to undo is reported
  local f i
  if (( TOUCHED_SHELL_JSON )) && have_omarchy; then
    stop_shell   # the running shell rewrites shell.json from memory, so it must be down while we restore
  fi
  for (( i = ${#UNDO[@]} - 1; i >= 0; i-- )); do
    f=${UNDO[i]}
    if [[ -f $SNAP$f.absent ]]; then                       # it did not exist before: take it away again
      rm -rf "$f" 2>/dev/null || echo "    ! could not remove $f" >&2
    elif [[ -e $SNAP$f ]]; then
      rm -rf "$f" 2>/dev/null || true                       # cp -a into an existing dir would nest, not replace
      mkdir -p "$(dirname "$f")"
      cp -a "$SNAP$f" "$f" 2>/dev/null || echo "    ! could not restore $f" >&2
    fi
  done
  if (( TOUCHED_SHELL_JSON )) && have_omarchy; then
    restart_shell_wait
    omarchy plugin list >/dev/null 2>&1 || echo "    ! the shell did not come back; run 'omarchy restart shell'" >&2
  fi
}
report_failure() {
  echo >&2
  echo "==> Installation failed. Nothing was applied: every change was rolled back." >&2
  local p
  for p in "${PROBLEMS[@]}"; do echo "    - $p" >&2; done
  if (( ${#WARNINGS[@]} )); then
    echo "    (not the cause, but worth knowing:)" >&2
    for p in "${WARNINGS[@]}"; do echo "    - $p" >&2; done
  fi
  echo "    Your desktop is the way it was before. Fix the problems above and run ./install.sh again." >&2
}
cleanup() { [[ -n $SNAP && -d $SNAP ]] && rm -rf "$SNAP"; }
on_exit() {
  local rc=$?
  if (( rc != 0 && ! DONE && ${#UNDO[@]} )); then rollback; fi
  cleanup
  exit $rc
}

# A require without its file is a hard Hyprland error ("module not found"), and it takes the
# whole config down with it. The generated orbital-keyboard.lua is the usual victim: deleted by
# hand, replaced by a dotfiles sync, or never written because the user has no Ghostty config.
reconcile_hypr_requires() {
  (( DRY )) && return 0
  [[ -f $HYPR/hyprland.lua ]] || return 0
  local mod re="" dangling=()
  for mod in orbital orbital-gaps orbital-bindings orbital-gestures orbital-keyboard; do
    if grep -qF "hypr.$mod\")" "$HYPR/hyprland.lua" && [[ ! -f $HYPR/$mod.lua ]]; then
      dangling+=("$mod"); re="${re:+$re|}$mod"
    fi
  done
  (( ${#dangling[@]} )) || return 0
  sed -i -E "/require\(\"hypr\.($re)\"\)/d" "$HYPR/hyprland.lua" \
    || { problem "could not remove the require(s) whose file is missing (${dangling[*]}) from $HYPR/hyprland.lua"; return 1; }
  say "Removed require(s) whose file is missing: ${dangling[*]}"
  echo "    (that part of the theme is off; re-run install.sh to get it back)"
}

uninstall() {
  say "Removing Orbital plugins, Hyprland hook and crash drop-in"
  for id in "${OVERLAYS[@]}" "${LIBS[@]}" "${BAR_IDS[@]}" "${EXTRA_WIDGETS[@]}" "${WIDGETS[@]%%:*}"; do
    have_omarchy && run omarchy plugin disable "$id" 2>/dev/null || true
    run rm -rf "$PLUGINS/$id"
  done
  [[ -f $CFG/ghostty/config ]] && run sed -i '/^# orbital-shortcuts/,/^# orbital-shortcuts end/d' "$CFG/ghostty/config"
  run rm -f "$HYPR/orbital.lua" "$HYPR/orbital-gaps.lua" "$HYPR/orbital-bindings.lua" "$HYPR/orbital-gestures.lua" "$HYPR/orbital-keyboard.lua" "$DROPIN/orbital.conf"
  [[ -f $HYPR/hyprland.lua ]] && run sed -i '/-- orbital$/d' "$HYPR/hyprland.lua"
  say "shell.json is not reverted automatically; restore a backup: $CFG/omarchy/shell.json.bak-orbital-*"
  systemctl --user daemon-reload 2>/dev/null || true
  say "Done. The theme itself: omarchy theme remove orbital. Baseline kept in $BASE."
}

if (( UNINSTALL )); then DONE=1; uninstall; exit 0; fi

desktop_id() { # first installed .desktop among candidates
  local c; for c in "$@"; do
    for d in /usr/share/applications ~/.local/share/applications; do [[ -f $d/$c.desktop ]] && { echo "$c"; return; }; done
  done
}

# Third-party (MIT) notification center: the bell after the clock. Installed with Omarchy's own
# `plugin add` (not bundled). It needs the network and is not part of the theme, so failing to
# fetch it is a warning, not a reason to abort: the layout is written without it.
NOTIF_ID="jankeesvw.notification-center"
NOTIF_URL="https://github.com/jankeesvw/omarchy-notification-center.git"
install_notification_center() {
  [[ -d $PLUGINS/$NOTIF_ID ]] && return 0
  say "Installing the notification center ($NOTIF_ID)"
  if (( DRY )); then echo "    [dry-run] omarchy plugin add $NOTIF_URL --enable --yes"; return 0; fi
  if ! omarchy plugin add "$NOTIF_URL" --enable --yes >/dev/null 2>&1 || [[ ! -d $PLUGINS/$NOTIF_ID ]]; then
    warn "the notification bell (third-party $NOTIF_ID) could not be installed; everything else is fine without it"
  fi
}

full_shell_json() {
  say "Full desktop: bar and layout in shell.json"
  local sj="$SJ" tmp
  ensure_dir "$CFG/omarchy" || { problem "could not create $CFG/omarchy"; return 1; }
  if [[ ! -f $sj ]]; then
    run cp "${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json" "$sj" || { problem "could not create $sj from Omarchy's defaults"; return 1; }
  fi
  run cp "$sj" "$sj.bak-orbital-$STAMP"
  if (( DRY )); then return 0; fi
  tmp="$(mktemp)"
  if ! jq --argjson bell "$( [[ -d $PLUGINS/$NOTIF_ID ]] && echo true || echo false )" --arg bellid "$NOTIF_ID" '
      .bar = (.bar // {}) |
      .bar.id = "orbital.floating-bar" | .bar.position = "bottom" | .bar.transparent = false |
      .bar.cornerRadius = 10 | .bar.floatGapScale = 0.5 | .bar.centerAnchor = "orbital.workspaces" |
      (.bar.layout // {}) as $l |
      ([($l.left // [])[], ($l.center // [])[], ($l.right // [])[]]) as $all |
      ($all | map(select(.id == "omarchy.indicators"))) as $ind |
      ($l.right // []) as $right |
      .bar.layout = {
        left:   [{id: "orbital.dock"}],
        center: [{id: "orbital.workspaces"}],
        right:  ( ($right | map(select(.id == "omarchy.tray")))
                + $ind
                + ($right | map(select(.id != "omarchy.tray" and .id != "omarchy.indicators"
                                        and .id != "orbital.divider" and .id != "orbital.keyboard" and .id != "orbital.clock" and .id != "omarchy.clock" and .id != $bellid)))
                + [{id: "orbital.keyboard"}, {id: "orbital.divider"},
                   {id: "orbital.clock", format: "HH:mm", formatAlt: "d MMMM '"'"'W'"'"'ww yyyy", verticalFormat: "HH\n—\nmm"}]
                + (if $bell then [{id: $bellid}] else [] end) )
      }
    ' "$sj" > "$tmp"; then
    problem "could not write the bar layout into $sj (jq failed; is the file valid JSON?)"
    rm -f "$tmp"; return 1
  fi
  jq -e . "$tmp" >/dev/null 2>&1 || { problem "the bar layout written to $sj is not valid JSON"; rm -f "$tmp"; return 1; }
  cat "$tmp" > "$sj"; rm -f "$tmp"
}

# Alt+Shift switches layouts (xkb grp:alt_shift_toggle). Uses the layouts you already have in
# ~/.config/hypr/input.lua, or --keyboard-layouts us,br. Written to its own file, loaded last.
# Ghostty binds Ctrl+Enter to fullscreen (and Ctrl+Shift+Enter, Ctrl+Tab to split-zoom/tabs), so apps in
# the terminal (Claude Code, editors, TUIs) never receive them. Free Ctrl+Enter, the one people hit by accident.
terminal_shortcuts() {
  local cfg="$CFG/ghostty/config" mark="# orbital-shortcuts"
  [[ -f $cfg ]] || return 0
  grep -qF "$mark" "$cfg" && return 0
  grep -qE '^[[:space:]]*keybind[[:space:]]*=[[:space:]]*ctrl\+enter=' "$cfg" && return 0
  say "Ghostty: freeing Ctrl+Enter for applications (was: toggle fullscreen)"
  if (( DRY )); then return 0; fi
  if ! printf '\n%s (added by the Orbital installer; remove this block to get Ctrl+Enter fullscreen back)\nkeybind = ctrl+enter=unbind\n%s end\n' "$mark" "$mark" >> "$cfg"; then
    problem "could not write to the Ghostty config ($cfg) to free Ctrl+Enter"; return 1
  fi
  omarchy restart terminal >/dev/null 2>&1 || warn "the terminal was not restarted; run 'omarchy restart terminal' to free Ctrl+Enter"
}

keyboard_setup() {
  local input="$HYPR/input.lua" layouts="$KBLAYOUTS" opts="compose:caps,shift:both_capslock_cancel"
  if [[ -f $input ]]; then
    [[ -n $layouts ]] || layouts="$(grep -E '^[[:space:]]*kb_layout[[:space:]]*=' "$input" | head -1 | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/' || true)"
    local existing; existing="$(grep -E '^[[:space:]]*kb_options[[:space:]]*=' "$input" | head -1 | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/' || true)"
    [[ -n $existing ]] && opts="$existing"
  fi
  if [[ $layouts != *,* ]]; then
    echo "    Keyboard: only one layout configured; pass --keyboard-layouts us,br to enable switching (the tray widget stays hidden until then)."
    return 0
  fi
  # xkb's own grp:alt_shift_toggle only fires when Alt goes down while Shift is already held, so the
  # usual Alt-then-Shift does nothing. Drop any grp: option and use two release binds instead: they
  # fire once per Alt+Shift chord in either order (mods at release time are ALT+SHIFT), and never on
  # Alt or Shift alone.
  opts="$(echo "$opts" | tr ',' '\n' | { grep -v '^grp:' || true; } | paste -sd, -)"
  say "Keyboard layouts: $layouts (Alt+Shift switches, either order)"
  ensure_dir "$HYPR" || { problem "could not create $HYPR"; return 1; }
  if (( DRY )); then return 0; fi
  if ! cat > "$HYPR/orbital-keyboard.lua" <<LUA
-- Orbital keyboard: layouts + Alt+Shift switching (loaded last). Edit or delete freely.
hl.config({ input = { kb_layout = "$layouts", kb_options = "$opts" } })
LUA
  then problem "could not write $HYPR/orbital-keyboard.lua"; return 1; fi
  if (( ALT_SHIFT )); then
    if ! cat >> "$HYPR/orbital-keyboard.lua" <<'LUA'
local next_layout = hl.dsp.exec_cmd("hyprctl switchxkblayout all next")
hl.bind("ALT + SHIFT + Shift_L", next_layout, { release = true })
hl.bind("ALT + SHIFT + Alt_L", next_layout, { release = true })
LUA
    then problem "could not add the Alt+Shift binds to $HYPR/orbital-keyboard.lua"; return 1; fi
  fi
  if ! grep -qF 'hypr.orbital-keyboard' "$HYPR/hyprland.lua" && ! printf 'require("hypr.orbital-keyboard") -- orbital\n' >> "$HYPR/hyprland.lua"; then
    problem "could not add the require to $HYPR/hyprland.lua"; return 1
  fi
}

# 4-finger horizontal swipe = workspace switch. Left alone when the user's own config already sets a gesture.
gestures_setup() {
  if (( ! GESTURES )); then echo "    Gestures: skipped (--no-gestures)"; return 0; fi
  if grep -qsE '^[[:space:]]*hl\.gesture\(' "$HYPR"/*.lua; then
    echo "    Gestures: your Hyprland config already defines one; leaving it alone."; return 0
  fi
  run cp "$REPO/hypr/orbital-gestures.lua" "$HYPR/orbital-gestures.lua" || { problem "could not install $HYPR/orbital-gestures.lua"; return 1; }
  if [[ -f $HYPR/hyprland.lua ]] && (( ! DRY )) && ! grep -qF 'hypr.orbital-gestures' "$HYPR/hyprland.lua" \
    && ! printf 'require("hypr.orbital-gestures") -- orbital\n' >> "$HYPR/hyprland.lua"; then
    problem "could not add the gestures require to $HYPR/hyprland.lua"; return 1
  fi
}

full_setup() {
  say "Full desktop: bindings, gaps, text size, dock pins"
  # Text size the layout was tuned at (shell, GTK and terminals), like the author's machine.
  if ! run omarchy display text size 10; then
    problem "'omarchy display text size 10' failed; --full promises the author's text size"
    return 1
  fi
  # Hyprland: bindings + gaps (gaps go BEFORE Omarchy's toggles so the gaps toggle still wins).
  if (( LAUNCHER_KEY )); then
    run cp "$REPO/hypr/orbital-bindings.lua" "$HYPR/orbital-bindings.lua" || { problem "could not install $HYPR/orbital-bindings.lua"; return 1; }
  else echo "    Launcher key: skipped (--no-launcher-key); bind it yourself: omarchy-shell shell toggle orbital.launcher"; fi
  run cp "$REPO/hypr/orbital-gaps.lua" "$HYPR/orbital-gaps.lua" || { problem "could not install $HYPR/orbital-gaps.lua"; return 1; }
  if [[ -f $HYPR/hyprland.lua ]] && (( ! DRY )); then
    if (( LAUNCHER_KEY )) && ! grep -qF 'hypr.orbital-bindings' "$HYPR/hyprland.lua" \
      && ! printf 'require("hypr.orbital-bindings") -- orbital\n' >> "$HYPR/hyprland.lua"; then
      problem "could not add the launcher binding require to $HYPR/hyprland.lua"; return 1
    fi
    if ! grep -qF 'hypr.orbital-gaps' "$HYPR/hyprland.lua"; then
      if grep -q 'require("default.hypr.toggles")' "$HYPR/hyprland.lua"; then
        sed -i 's|^require("default.hypr.toggles")|require("hypr.orbital-gaps") -- orbital\n&|' "$HYPR/hyprland.lua" \
          || { problem "could not add the gaps require to $HYPR/hyprland.lua"; return 1; }
      elif ! printf 'require("hypr.orbital-gaps") -- orbital\n' >> "$HYPR/hyprland.lua"; then
        problem "could not add the gaps require to $HYPR/hyprland.lua"; return 1
      fi
    fi
  fi
  keyboard_setup || return 1
  gestures_setup || return 1
  terminal_shortcuts || return 1
  # Dock pins: only if the user has none yet; from what is actually installed.
  local pins="$HOME/.local/state/omarchy/orbital-dock.json"
  if [[ ! -f $pins ]] && (( ! DRY )); then
    local b t f entries=()
    b="$(xdg-settings get default-web-browser 2>/dev/null | sed 's/\.desktop$//' || true)"
    t="$(desktop_id com.mitchellh.ghostty Alacritty kitty foot)"
    f="$(desktop_id org.gnome.Nautilus org.kde.dolphin thunar)"
    for e in "$b" "$t" "$f"; do [[ -n $e ]] && entries+=("$e"); done
    if (( ${#entries[@]} )); then
      ensure_dir "$(dirname "$pins")" || { problem "could not create $(dirname "$pins")"; return 1; }
      if ! printf '%s\n' "${entries[@]}" | jq -R '{key: (. | ascii_downcase), entry: .}' | jq -s '{version: 1, pinned: .}' > "$pins"; then
        problem "could not write the default dock pins to $pins"; return 1
      fi
    fi
  fi
}

# ---------------------------------------------------------------------------------------------
# Phase 1 - checks. Nothing here touches the system: every problem that can be seen up front is
# collected and reported together, so one run tells the user everything that is wrong.
# ---------------------------------------------------------------------------------------------
writable_path() { # a path we may have to create: writable if the closest existing parent is
  local d=$1
  while [[ ! -e $d ]]; do
    local p; p="$(dirname "$d")"
    [[ $p == "$d" ]] && return 1
    d=$p
  done
  [[ -w $d ]]
}

checks() {
  local c d id
  for c in python3 jq bash; do command -v "$c" >/dev/null || problem "missing requirement: $c"; done
  have_omarchy || problem "missing requirement: omarchy (this is an Omarchy theme)"

  # The package has to be complete before we start: a missing plugin folder is a broken download.
  for d in "$REPO"/plugins/*/; do
    id="$(basename "$d")"
    if [[ $id == orbital.ui ]]; then
      [[ -f $d/OrbitalTokens.qml ]] || problem "the package is incomplete: plugins/$id/OrbitalTokens.qml is missing"
    elif [[ ! -f $d/manifest.json ]]; then
      problem "the package is incomplete: plugins/$id/manifest.json is missing"
    fi
  done
  for f in hypr/orbital.lua systemd/orbital.conf .omarchy-theme.yml; do
    [[ -f $REPO/$f ]] || problem "the package is incomplete: $f is missing"
  done

  # The schema is Omarchy's, not ours: ask the real CLI before installing anything.
  if have_omarchy; then
    for d in "$REPO"/plugins/*/; do
      id="$(basename "$d")"
      [[ -f $d/manifest.json ]] || continue
      trip validate && { problem "omarchy plugin validate $id failed"; continue; }
      omarchy plugin validate "$d" >/dev/null 2>&1 || problem "this Omarchy rejects the manifest of $id (omarchy plugin validate)"
    done
  fi

  # shell.json is how plugins get enabled; without it (and without a default to copy) we cannot work.
  if [[ ! -f $SJ && ! -f $OMARCHY_PATH/config/omarchy/shell.json ]]; then
    problem "no $SJ and no default at $OMARCHY_PATH/config/omarchy/shell.json to create it from"
  elif [[ -f $SJ ]] && ! jq -e . "$SJ" >/dev/null 2>&1; then
    problem "$SJ is not valid JSON; fix or remove it and run this again"
  fi

  # Every place we will write to has to be writable before we start.
  for d in "$PLUGINS" "$BACKUPS" "$HYPR" "$DROPIN" "$BASE"; do
    writable_path "$d" || problem "cannot write to $d (or to create it)"
  done
  [[ -f $HYPR/hyprland.lua ]] && { [[ -w $HYPR/hyprland.lua ]] || problem "$HYPR/hyprland.lua is not writable"; } \
    || problem "no $HYPR/hyprland.lua to hook into (this does not look like an Omarchy Hyprland setup)"

  # `omarchy plugin enable` needs a live shell; without it nothing can be enabled and every later
  # step would fail for the wrong reason. A shell that is still starting up gets a chance to answer.
  if have_omarchy && ! wait_shell; then
    problem "the Omarchy shell is not answering ('omarchy plugin list' failed); start it and run this again"
  fi
  (( ${#PROBLEMS[@]} == 0 ))
}

# ---------------------------------------------------------------------------------------------
# Phase 2 - apply. Each step reports what went wrong and unwinds; nothing is declared done yet.
# ---------------------------------------------------------------------------------------------
apply_plugins() {
  local d id
  say "Installing plugins into $PLUGINS"
  if (( DRY )); then
    for d in "$REPO"/plugins/*/; do echo "    [dry-run] install plugins/$(basename "$d") into $PLUGINS"; done
    return 0
  fi
  ensure_dir "$PLUGINS" && ensure_dir "$BACKUPS" || { problem "could not create $PLUGINS"; return 1; }
  for d in "$REPO"/plugins/*/; do
    id="$(basename "$d")"
    trip plugins && { problem "could not install the plugins (simulated failure)"; return 1; }
    if [[ -d $PLUGINS/$id ]] && ! diff -rq "$d" "$PLUGINS/$id" >/dev/null 2>&1; then
      snapshot "$PLUGINS/$id"
      mv "$PLUGINS/$id" "$BACKUPS/$id.$STAMP" || { problem "could not move the old $id aside"; return 1; }
    fi
    if [[ ! -d $PLUGINS/$id ]]; then
      snapshot "$PLUGINS/$id"
      cp -r "$d" "$PLUGINS/$id" || { problem "could not copy plugins/$id into $PLUGINS"; return 1; }
    fi
    chmod +x "$PLUGINS/$id"/orbital-* 2>/dev/null || true
  done
  # A copy that silently lost a file is exactly the "installed but broken" case we must not ship.
  for d in "$REPO"/plugins/*/; do
    id="$(basename "$d")"
    diff -rq "$d" "$PLUGINS/$id" >/dev/null 2>&1 || { problem "plugins/$id was not copied completely"; return 1; }
  done
}

apply_baseline() {
  say "Creating the accent picker baseline in $BASE"
  ensure_dir "$BASE" || { problem "could not create $BASE"; return 1; }
  (( DRY )) && return 0
  (cd "$REPO" && tar cf - --exclude=./plugins --exclude=./hypr --exclude=./systemd --exclude=./scripts \
     --exclude=./docs --exclude=./backgrounds --exclude=./.git --exclude=./install.sh \
     --exclude=./README.md --exclude=./CHANGELOG.md --exclude='./LICENSE*' --exclude='*.png' --exclude='*.jpg' .) \
    | tar xf - -C "$BASE" || { problem "could not write the pristine theme copy to $BASE"; return 1; }
  [[ -f $BASE/colors.toml ]] || { problem "the baseline in $BASE has no colors.toml"; return 1; }
}

apply_hypr() {
  say "Installing the Hyprland part ($HYPR/orbital.lua)"
  ensure_dir "$HYPR" || { problem "could not create $HYPR"; return 1; }
  trip hypr && { problem "could not install $HYPR/orbital.lua (simulated failure)"; return 1; }
  if (( DRY )); then echo "    [dry-run] install $REPO/hypr/orbital.lua -> $HYPR/orbital.lua (+ require in hyprland.lua)"; return 0; fi
  snapshot "$HYPR/orbital.lua"
  cp "$REPO/hypr/orbital.lua" "$HYPR/orbital.lua" || { problem "could not install $HYPR/orbital.lua"; return 1; }
  if [[ -f $HYPR/hyprland.lua ]] && ! grep -qF "$MARK" "$HYPR/hyprland.lua"; then
    snapshot "$HYPR/hyprland.lua"
    cp "$HYPR/hyprland.lua" "$HYPR/hyprland.lua.bak-orbital-$STAMP"
    if ! printf '\n-- Orbital glass, borders, animations (loaded last so it wins over earlier settings).\n%s\n' "$MARK" >> "$HYPR/hyprland.lua"; then
      problem "could not add the require to $HYPR/hyprland.lua"; return 1
    fi
  fi
  reconcile_hypr_requires
}

apply_dropin() {
  say "Installing the crash-watch drop-in"
  ensure_dir "$DROPIN" || { problem "could not create $DROPIN"; return 1; }
  trip dropin && { problem "could not install the crash-watch drop-in (simulated failure)"; return 1; }
  if (( DRY )); then echo "    [dry-run] install $REPO/systemd/orbital.conf -> $DROPIN/orbital.conf"; return 0; fi
  snapshot "$DROPIN/orbital.conf"
  cp "$REPO/systemd/orbital.conf" "$DROPIN/orbital.conf" || { problem "could not install $DROPIN/orbital.conf"; return 1; }
  if ! systemctl --user daemon-reload 2>/dev/null; then
    warn "systemd did not accept 'daemon-reload'; the crash dialog only matters if a process crashes"
  fi
  systemctl --user try-restart omarchy-crash-watch >/dev/null 2>&1 || true
}

restart_shell_wait() { # the running shell keeps its config in memory and rewrites shell.json on every change
  local n            # (e.g. `plugin enable`), so a hand edit is lost unless the shell reloads it first
  omarchy restart shell >/dev/null 2>&1 || true
  for n in $(seq 1 30); do omarchy plugin list >/dev/null 2>&1 && break; nap 2; done
  nap 3
}
stop_shell() { # same kill loop as omarchy-restart-shell: returns only once the shell has fully exited
  while timeout 5 quickshell kill -p "$OMARCHY_PATH/shell" --any-display >/dev/null 2>&1; do :; done
}
wait_shell() { # `plugin enable` needs a responsive shell; right after a rescan or a restart it is busy
  local n; for n in $(seq 1 15); do omarchy plugin list >/dev/null 2>&1 && return 0; nap 2; done; return 1
}

apply_shell_json() {
  # A fresh Omarchy has no ~/.config/omarchy/shell.json and `plugin enable` then silently records
  # nothing, so create it from the defaults first.
  if [[ ! -f $SJ ]]; then
    say "Creating $SJ from Omarchy's defaults"
    ensure_dir "$CFG/omarchy" || { problem "could not create $CFG/omarchy"; return 1; }
    if (( DRY )); then
      echo "    [dry-run] cp $OMARCHY_PATH/config/omarchy/shell.json $SJ"
    else
      cp "$OMARCHY_PATH/config/omarchy/shell.json" "$SJ" || { problem "could not create $SJ from Omarchy's defaults"; return 1; }
      chmod 644 "$SJ"
    fi
  fi
  # From here on the shell itself rewrites shell.json (every `plugin enable` goes through it), so this
  # is the file a rollback has to put back: snapshot it once, before anything touches it.
  snapshot "$SJ"; TOUCHED_SHELL_JSON=1
  if (( FULL )); then
    install_notification_center
    if (( ! DRY )); then stop_shell; fi   # the shell rewrites shell.json from memory when it exits
    full_shell_json || return 1
    if (( ! DRY )); then restart_shell_wait; fi
  fi
  (( DRY )) || omarchy-shell shell rescanPlugins >/dev/null 2>&1 || warn "the plugin rescan did not answer; continuing"
  (( DRY )) || nap 2
  if (( ! DRY )) && ! wait_shell; then
    problem "the Omarchy shell stopped answering after the plugin rescan; nothing could be enabled"
    return 1
  fi
}

enable_verified() { # `plugin enable` talks to the running shell; confirm it stuck, retry if not
  local id="$1" n
  for n in 1 2 3 4 5; do
    trip enable && { problem "$id could not be enabled (simulated failure)"; return 1; }
    omarchy plugin enable "$id" >/dev/null 2>&1 || true
    omarchy plugin list 2>/dev/null | grep -E "^$id +enabled" >/dev/null && { echo "    enabled $id"; return 0; }
    nap 2
  done
  if ! omarchy plugin list >/dev/null 2>&1; then
    problem "$id could not be enabled and the shell is no longer answering"
  else
    problem "$id is installed but 'omarchy plugin enable $id' did not stick"
  fi
  return 1
}

# `omarchy plugin enable --section` reports "omarchy-shell is not responding" under a burst of calls
# even when the change lands, so the exit code is not the truth: read the layout back instead.
place_verified() { # <id> <section>: confirm the widget is really in the bar layout
  local id="$1" sec="$2" n
  for n in 1 2 3 4 5; do
    trip widgets && { problem "could not place $id in the bar (simulated failure)"; return 1; }
    omarchy plugin enable "$id" --section "$sec" >/dev/null 2>&1 || true
    if in_bar "$id"; then echo "    placed $id in $sec"; return 0; fi
    nap 2
  done
  problem "could not place $id in the $sec section of the bar"
  return 1
}
in_bar() { jq -e --arg id "$1" '[.bar.layout[]?[]?.id] | index($id)' "$SJ" >/dev/null 2>&1; }
move_verified() { # <id> <section> <index>: same shell-busy flakiness, so confirm the position
  local id="$1" sec="$2" idx="$3" n at
  for n in 1 2 3 4 5; do
    trip widgets && { problem "could not move $id to the end of the bar (simulated failure)"; return 1; }
    omarchy bar move "$id" --section "$sec" --index "$idx" >/dev/null 2>&1 || true
    at="$(jq -r --arg sec "$sec" --argjson i "$idx" '.bar.layout[$sec][$i].id // empty' "$SJ" 2>/dev/null || true)"
    [[ $at == "$id" ]] && return 0
    nap 2
  done
  problem "$id could not be moved to the end of the $sec section of the bar"
  return 1
}

apply_enable() {
  local id w
  say "Enabling plugins"
  for id in "${OVERLAYS[@]}"; do
    (( DRY )) && { echo "    [dry-run] enable $id"; continue; }
    enable_verified "$id" || return 1
  done
  # The theme ships its own bar, so use it: without this the plugins install but the user keeps
  # Omarchy's stock bar. Reverting is one command, printed below.
  (( DRY )) && return 0
  TOUCHED_SHELL_JSON=1
  local cur; cur="$(jq -r '.bar.id // "omarchy.bar"' "$SJ" 2>/dev/null || echo omarchy.bar)"
  if [[ $cur != orbital.floating-bar && $cur != orbital.bar ]]; then
    enable_verified orbital.floating-bar || return 1
    echo "    (revert with: omarchy plugin enable $cur)"
  fi
  # Only the bar in .bar.id is ever loaded: if the other one is still enabled, turn it off.
  local want other
  want="$(jq -r '.bar.id // ""' "$SJ" 2>/dev/null || true)"
  if [[ $want == orbital.bar ]]; then other=orbital.floating-bar; else other=orbital.bar; fi
  if [[ $want != "$other" ]] && omarchy plugin list 2>/dev/null | grep -qE "^$other +enabled"; then
    if ! omarchy plugin disable "$other" >/dev/null 2>&1; then
      problem "could not disable the unused bar ($other)"; return 1
    fi
    echo "    disabled the unused bar: $other"
  fi
  (( BAR )) || return 0
  if (( FULL )); then echo "    Bar layout already written by --full."; return 0; fi
  if (( DRY )); then
    for w in "${WIDGETS[@]}" "${EXTRA_WIDGETS[@]}"; do echo "    [dry-run] place ${w%%:*} in the bar (${w##*:})"; done
    return 0
  fi
  for w in "${WIDGETS[@]}"; do place_verified "${w%%:*}" "${w##*:}" || return 1; done
  for id in "${EXTRA_WIDGETS[@]}"; do place_verified "$id" right || return 1; done
  # `enable --section` inserts at the START of a section; right-hand widgets belong at the end
  # (keyboard, divider, clock), so move them there.
  local n; n="$(jq '.bar.layout.right | length' "$SJ" 2>/dev/null || echo 0)"
  if (( n > 0 )); then
    # keyboard, divider, clock, each to the last slot: the previous one ends up just before it.
    for id in orbital.keyboard orbital.divider orbital.clock; do
      move_verified "$id" right $((n - 1)) || return 1
    done
  fi
}

apply_extras() {
  if (( FULL )); then full_setup || return 1; elif (( TERM_FIX )); then terminal_shortcuts || return 1; fi
  (( DRY )) || hyprctl reload >/dev/null 2>&1 || warn "'hyprctl reload' did not answer; the new glass/borders load on the next Hyprland reload"
}

# ---------------------------------------------------------------------------------------------
# Phase 3 - verify. Read the real state back: the install is only "done" if everything the theme
# promises is actually there. Anything missing means rollback, not a warning.
# ---------------------------------------------------------------------------------------------
verify_all() {
  local list id w
  say "Verifying the installation"
  (( DRY )) && { echo "    [dry-run] would verify: plugins enabled, bar in use, widgets placed, no dangling require"; return 0; }
  trip verify && { problem "verification failed (simulated failure)"; return 1; }

  list="$(omarchy plugin list 2>/dev/null || true)"
  for id in "${OVERLAYS[@]}" "${EXTRA_WIDGETS[@]}" "${WIDGETS[@]%%:*}"; do
    grep -qE "^$id +enabled" <<<"$list" || problem "$id is installed but not enabled after the install"
  done

  jq -e . "$SJ" >/dev/null 2>&1 || problem "$SJ is not valid JSON after the install"
  local bar other; bar="$(jq -r '.bar.id // ""' "$SJ" 2>/dev/null || true)"
  case $bar in
    orbital.floating-bar|orbital.bar) ;;
    *) problem "the bar in use is '${bar:-none}', not an Orbital one" ;;
  esac
  # Only the bar named in .bar.id is ever loaded, so exactly one of the two may be enabled.
  if [[ $bar == orbital.bar ]]; then other=orbital.floating-bar; else other=orbital.bar; fi
  grep -qE "^$bar +enabled" <<<"$list" || problem "the bar in use ($bar) is not enabled after the install"
  if grep -qE "^$other +enabled" <<<"$list"; then
    problem "both bars are enabled at once ($bar and $other); the shell would load only one"
  fi
  if (( BAR )); then
    local left right
    left="$(jq -r '[.bar.layout.left[]?.id] | join(" ")' "$SJ" 2>/dev/null || true)"
    right="$(jq -r '[.bar.layout.right[]?.id] | join(" ")' "$SJ" 2>/dev/null || true)"
    grep -qw orbital.dock <<<"$left" || problem "the dock is not in the left section of the bar (left: ${left:-empty})"
    for w in orbital.keyboard orbital.divider orbital.clock; do
      grep -qw "$w" <<<"$right" || problem "$w is not in the right section of the bar (right: ${right:-empty})"
    done
    # keyboard, then the hairline, then the clock: the order is the whole point of the divider
    local order; order="$(jq -r '[.bar.layout.right[]?.id] | join(" ")' "$SJ" 2>/dev/null || true)"
    [[ $(awk '{for (i=1;i<=NF;i++) {if ($i=="orbital.keyboard") k=i; if ($i=="orbital.divider") d=i; if ($i=="orbital.clock") c=i}}
                       END {print (k && d && c && k<d && d<c) ? "yes" : "no"}' <<<"$order") == yes ]] \
      || problem "the right side of the bar is out of order (want keyboard, divider, clock: ${order:-empty})"
    grep -qw orbital.workspaces <<<"$(jq -r '[.bar.layout[]?[]?.id] | join(" ")' "$SJ" 2>/dev/null || true)" \
      || problem "orbital.workspaces is not in the bar layout"
  fi
  if (( FULL )); then
    [[ $(jq -r '.bar.position' "$SJ") == bottom ]] || problem "the bar should be at the bottom with --full"
  fi

  # Every file the theme hooks into has to exist, or Hyprland takes the whole config down.
  for f in "$HYPR/hyprland.lua" "$HYPR/orbital.lua" "$DROPIN/orbital.conf"; do
    [[ -f $f ]] || problem "$f is missing after the install"
  done
  if [[ -f $HYPR/hyprland.lua ]]; then
    local mod dangling=()
    for mod in orbital orbital-gaps orbital-bindings orbital-gestures orbital-keyboard; do
      grep -qF "hypr.$mod\")" "$HYPR/hyprland.lua" && [[ ! -f $HYPR/$mod.lua ]] && dangling+=("$mod")
    done
    (( ${#dangling[@]} == 0 )) || problem "require() with no file: ${dangling[*]} (Hyprland would refuse to load the config)"
  fi
  for d in "$REPO"/plugins/*/; do
    id="$(basename "$d")"
    diff -rq "$d" "$PLUGINS/$id" >/dev/null 2>&1 || problem "plugins/$id in $PLUGINS differs from the package"
  done
  [[ -f $BASE/colors.toml ]] || problem "the color picker baseline ($BASE/colors.toml) is missing"

  (( ${#PROBLEMS[@]} == 0 ))
}

# ---------------------------------------------------------------------------------------------
# Run it.
# ---------------------------------------------------------------------------------------------
if ! checks; then
  DONE=1   # nothing was touched; the exit handler must not try to roll back
  echo >&2
  echo "==> Cannot install yet. Nothing was changed." >&2
  for p in "${PROBLEMS[@]}"; do echo "    - $p" >&2; done
  exit 1
fi

# Optional: the plugins shell out to these. None is fatal, so this only names what goes empty,
# instead of leaving a blank widget with no explanation.
OPTIONAL_DEPS=(
  "hyprctl:gaps for the floating bar and the keyboard device list"
  "xkbcli:exotic layouts in the keyboard widget"
  "curl:weather in the clock"
  "timedatectl:timezone list for the world clock"
  "omarchy-reminder:reminder indicator"
  "omarchy-update-available:system update indicator"
  "omarchy-voxtype-status:dictation indicator"
)
for d in "${OPTIONAL_DEPS[@]}"; do
  command -v "${d%%:*}" >/dev/null || warn "${d%%:*} not found - ${d#*:} will be empty"
done
if (( ${#WARNINGS[@]} )) && ! (( DRY )); then
  say "Optional dependencies missing (the theme installs anyway):"
  for d in "${WARNINGS[@]}"; do echo "    $d"; done
fi

SNAP="$(mktemp -d)"
trap on_exit EXIT

ok=1
apply_plugins    || ok=0
(( ok )) && { apply_baseline || ok=0; }
(( ok )) && { apply_hypr      || ok=0; }
(( ok )) && { apply_dropin    || ok=0; }
(( ok )) && { apply_shell_json || ok=0; }
(( ok )) && { apply_enable    || ok=0; }
(( ok )) && { apply_extras    || ok=0; }
if (( ok )) && ! verify_all; then ok=0; fi

if (( ! ok )); then
  report_failure
  exit 1
fi

DONE=1
if (( ${#WARNINGS[@]} )); then
  say "Installed, with warnings (nothing is broken by these):"
  for d in "${WARNINGS[@]}"; do echo "    $d"; done
fi
if (( RESTART )) && (( ! DRY )); then
  say "Restarting the shell"
  if ! omarchy restart shell; then
    echo "    The shell did not restart; run 'omarchy restart shell' to see the theme." >&2
  fi
fi
say "Now apply the theme: omarchy theme set orbital"
echo "    Optional: set your avatar with  ~/.config/omarchy/plugins/orbital.account/orbital-avatar <image>"
