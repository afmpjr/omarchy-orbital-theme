#!/usr/bin/env bash
# Shortcut-conflict audit for an Omarchy desktop (works on any machine, not only Orbital).
#   scripts/keybind-audit.sh          # prints a report; exit 1 when a HIGH finding exists
#
# Checks:
#  1. Hyprland: the same mod+key bound more than once (the later bind silently wins).
#  2. Hyprland: global binds WITHOUT Super on keys apps use for themselves (Ctrl/Alt/Shift-only
#     chords steal them from every application). Desktop classics (Alt+Tab, Alt+F4) and XF86 keys are fine.
#  3. Terminal (Ghostty): built-in shortcuts that shadow keys TUIs and shells expect
#     (Ctrl+Enter = fullscreen, Ctrl+Shift+Enter = zoom split, Ctrl+Tab = tabs) and are still active.
#  4. Orbital's own additions: Alt+Shift (release binds) can fire after Alt+Shift+<key> chords in editors.
# Read-only: never changes anything.
set -uo pipefail
high=0; warn=0
say()  { printf '%s\n' "$*"; }
HIGH() { printf '  [HIGH] %s\n' "$*"; high=$((high+1)); }
WARN() { printf '  [warn] %s\n' "$*"; warn=$((warn+1)); }
OK()   { printf '  [ ok ] %s\n' "$*"; }
mods() { local m=$1 s=""; ((m&64)) && s+="SUPER+"; ((m&4)) && s+="CTRL+"; ((m&8)) && s+="ALT+"; ((m&1)) && s+="SHIFT+"; printf '%s' "${s%+}"; }

say "== 1. Hyprland: duplicate binds"
if command -v hyprctl >/dev/null && binds="$(hyprctl binds -j 2>/dev/null)" && [[ -n $binds && $binds != "[]" ]]; then
  dups="$(jq -r 'map(select(.key != "" and (.key | test("^switch:") | not)))
                 | group_by([.modmask, (.key|ascii_downcase), (.submap // ""), .release, .mouse])
                 | .[] | select(length > 1)
                 | "\(.[0].modmask)\t\(.[0].key)\t\(map(.description // .dispatcher) | join("  |  "))"' <<<"$binds")"
  if [[ -z $dups ]]; then OK "none"; else
    while IFS=$'\t' read -r m k d; do WARN "$(mods "$m")+$k is bound more than once: $d"; done <<<"$dups"
  fi

  say; say "== 2. Hyprland: global binds without Super on app-level keys"
  risky="$(jq -r '.[] | select(.modmask != 0 and (.modmask % 128) < 64)
                  | select([.modmask | (. / 1 | floor)] | length > 0)
                  | select((.modmask == 1 or .modmask == 4 or .modmask == 8 or .modmask == 5 or .modmask == 9))
                  | select(.key | test("^(XF86|Print|mouse|switch)"; "i") | not)
                  | select((.modmask == 8 and (.key | test("^(TAB|F4)$"; "i"))) | not)
                  | "\(.modmask)\t\(.key)\t\(.description // .dispatcher)"' <<<"$binds" | sort -u)"
  if [[ -z $risky ]]; then OK "none"; else
    while IFS=$'\t' read -r m k d; do WARN "$(mods "$m")+$k -> $d  (steals this chord from every app)"; done <<<"$risky"
  fi
  # bare keys and Shift-only binds are the worst offenders
  # a bare printable/navigation key would break typing everywhere; F-keys are only a warning
  bare="$(jq -r '.[] | select(.modmask == 0) | select(.key | test("^(XF86|Print|mouse|switch)"; "i") | not) | "\(.key)\t\(.description // .dispatcher)"' <<<"$binds")"
  if [[ -n $bare ]]; then
    while IFS=$'\t' read -r k d; do
      if [[ $k =~ ^[Ff][0-9]+$ ]]; then WARN "bare $k -> $d (an app using $k never gets it)"
      else HIGH "bare key $k has no modifier -> $d (breaks typing/navigation in every app)"; fi
    done <<<"$bare"
  fi
else
  say "  (Hyprland is not running here; skipped)"
fi

say; say "== 3. Terminal shortcuts that shadow app keys (Ghostty)"
if command -v ghostty >/dev/null; then
  eff="$(ghostty +list-keybinds 2>/dev/null)"
  check() { # <chord> <what it does by default> <severity>
    if grep -qF "keybind = $1=" <<<"$eff" && ! grep -qF "keybind = $1=unbind" <<<"$eff"; then
      local action; action="$(grep -F "keybind = $1=" <<<"$eff" | head -1 | sed 's/.*=//')"
      case $3 in HIGH) HIGH "$1 still runs '$action' in Ghostty (apps like Claude Code / editors never see it). Fix: keybind = $1=unbind";;
                 *)    WARN "$1 still runs '$action' in Ghostty. Fix: keybind = $1=unbind";; esac
    else OK "$1 is free for applications"; fi
  }
  check "ctrl+enter" "toggle_fullscreen" HIGH
  check "ctrl+shift+enter" "toggle_split_zoom" warn
  check "ctrl+tab" "next_tab" warn
  check "ctrl+shift+tab" "previous_tab" warn
else
  say "  (Ghostty not installed; skipped)"
fi

say; say "== 4. Orbital additions"
if [[ -f $HOME/.config/hypr/orbital-keyboard.lua ]]; then
  WARN "Alt+Shift switches keyboard layouts on release: an editor chord such as Alt+Shift+Down (VS Code: copy line) also toggles the layout. Edit ~/.config/hypr/orbital-keyboard.lua to use another chord if that bites."
else OK "no Alt+Shift layout binds installed"; fi
if [[ -f $HOME/.config/hypr/orbital-bindings.lua ]]; then
  WARN "orbital-bindings.lua rebinds SUPER+S (Omarchy's own binding for it is removed). Change it there if you want to keep the stock one."
fi

say; say "Summary: $high high, $warn warnings"
(( high == 0 ))
