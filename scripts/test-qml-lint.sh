#!/usr/bin/env bash
# QML syntax gate: every shipped .qml must parse under qmllint.
# Unresolved host modules (Quickshell, qs.*) surface as warnings, never as
# failures here: qmllint exits non-zero only on real errors. When the Omarchy
# shell modules are present, they are added to the import path so type
# checking goes further. Skips (not fails) where no qmllint exists.
set -euo pipefail
cd "$(dirname "$0")/.."

LINT=""
for c in qmllint /usr/lib/qt6/bin/qmllint /usr/lib/x86_64-linux-gnu/qt6/bin/qmllint; do
  if [[ -x $c ]] || command -v "$c" >/dev/null 2>&1; then LINT="$c"; break; fi
done
if [[ -z $LINT ]]; then echo "skip  - qmllint not found (no Qt lint on this machine)"; exit 0; fi

IMPORTS=()
add_import() { if [[ -d $1 ]]; then IMPORTS+=(-I "$1"); fi; }
SHIM="$(mktemp -d)"; trap 'rm -rf "$SHIM"' EXIT
if [[ -d /usr/share/omarchy/shell ]]; then
  mkdir -p "$SHIM/qs"
  ln -s /usr/share/omarchy/shell/Commons "$SHIM/qs/Commons" 2>/dev/null || true
  ln -s /usr/share/omarchy/shell/Ui "$SHIM/qs/Ui" 2>/dev/null || true
  add_import "$SHIM"
fi
add_import /usr/lib/qt6/qml
add_import /usr/lib/x86_64-linux-gnu/qt6/qml

fail=0; count=0
while IFS= read -r f; do
  count=$((count + 1))
  if ! out=$("$LINT" "${IMPORTS[@]}" "$f" 2>&1); then
    fail=1; echo "FAIL - $f:"; echo "$out" | head -10
  fi
done < <(find plugins -name '*.qml' | sort)
(( fail == 0 )) || exit 1
echo "ok   - $count QML files parse under qmllint ($LINT)"
