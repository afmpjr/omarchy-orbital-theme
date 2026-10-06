#!/usr/bin/env bash
# Headless interaction tests for bin/orbital-setup: piped keystrokes drive the
# real menus in a sandbox HOME and assert the side effects. Every case runs
# under `timeout` so a stuck read fails loudly instead of hanging the suite.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; export HOME="$T/home" ORBITAL_SETUP_FORCE_TTY=1
mkdir -p "$HOME/.config/omarchy/plugins/orbital.account" "$HOME/.config/hypr"
cp "$REPO/plugins/orbital.account/orbital-widgets-lock" "$HOME/.config/omarchy/plugins/orbital.account/"
cp "$REPO/plugins/orbital.account/orbital-avatar" "$HOME/.config/omarchy/plugins/orbital.account/" 2>/dev/null || true
SETUP="$REPO/bin/orbital-setup"
pass=0; fail=0
ok() { pass=$((pass+1)); echo "ok   - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }

# 1. quit immediately, nothing touched
printf 'q' | timeout 10 bash "$SETUP" >/dev/null 2>&1 || bad "quit hangs or errors"
[[ ! -f $HOME/.config/hypr/orbital-keyboard.lua ]] || bad "quit wrote files"
(( fail == 0 )) && ok "quit is clean"

# 2. keyboard: us,br layout file with Alt+Shift binds
printf 'jjjj\nj\nq' | timeout 15 bash "$SETUP" >/dev/null 2>&1 || bad "keyboard flow errors"
grep -q 'kb_layout = "us,br"' "$HOME/.config/hypr/orbital-keyboard.lua" 2>/dev/null || bad "keyboard layout not written"
grep -q 'ALT + SHIFT' "$HOME/.config/hypr/orbital-keyboard.lua" 2>/dev/null || bad "Alt+Shift binds missing"
(( fail == 0 )) && ok "keyboard writes us,br + Alt+Shift"

# 3. widgets lock toggle writes state
printf 'jjj\n\nq' | timeout 15 bash "$SETUP" >/dev/null 2>&1 || bad "widgets flow errors"
[[ $(cat "$HOME/.local/state/omarchy/orbital-widgets-lock" 2>/dev/null) == 0 ]] || bad "lock toggle did not unlock"
(( fail == 0 )) && ok "widgets lock toggles"

# 4. gaps preset writes lua
printf 'jjjjjjjj\n\nq' | timeout 15 bash "$SETUP" >/dev/null 2>&1 || bad "gaps flow errors"
grep -q 'gaps_in = 8, gaps_out = 12' "$HOME/.config/hypr/orbital-gaps.lua" 2>/dev/null || bad "gaps preset not written"
(( fail == 0 )) && ok "gaps preset writes lua"

# 5. bar section navigates without omarchy present (no crash, no hang)
printf 'j\n\nq' | timeout 15 bash "$SETUP" >/dev/null 2>&1 || bad "bar flow errors"
(( fail == 0 )) && ok "bar section is hang-free without omarchy"

# 6. Esc backs out of a section to main, then quits
printf 'jjjjjj\n\x1bq' | timeout 15 bash "$SETUP" >/dev/null 2>&1 || bad "esc-back errors"
(( fail == 0 )) && ok "esc returns to main"

# 7. bar position: each pick passes exactly one position value (regression:
# a && || chain used to accumulate echoes into multi-line arguments)
mkdir -p "$T/bin"
cat > "$T/bin/omarchy" <<'STUB'
#!/usr/bin/env bash
echo "omarchy $*" >> "$HOME/omarchy-calls.log"
exit 0
STUB
chmod +x "$T/bin/omarchy"
export PATH="$T/bin:$PATH"
i=0
for pos in bottom top left right; do
  : > "$HOME/omarchy-calls.log"
  downs=""; j=0; while (( j < i )); do downs+="j"; j=$((j+1)); done
  printf "jj\n%s\nq" "$downs" | timeout 15 bash "$SETUP" >/dev/null 2>&1 || bad "position $pos errors"
  [[ $(wc -l < "$HOME/omarchy-calls.log") -eq 2 ]] || bad "position $pos leaked extra lines"
  grep -qx "omarchy bar position $pos" "$HOME/omarchy-calls.log" || bad "position $pos not passed exactly"
  i=$((i+1))
done
(( fail == 0 )) && ok "bar position passes exact value for all 4"

rm -rf "$T"
if (( fail > 0 )); then echo "SETUP TESTS: $fail failed"; exit 1; fi
echo "SETUP TESTS: all $pass passed"
