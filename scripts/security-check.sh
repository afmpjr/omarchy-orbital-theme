#!/usr/bin/env bash
# Repository-wide security linter for omarchy-orbital-theme (all plugins & scripts).
set -uo pipefail
cd "$(dirname "$(realpath "$0")")/.." || exit 1

fail=0
mapfile -t qml < <(find plugins -name '*.qml' | sort)

flag() {
  local label="$1" re="$2"; shift 2
  local hits="" f n rest prev
  while IFS=: read -r f n rest; do
    [[ $rest == *"sec-ok:"* ]] && continue
    prev=$([[ $n -gt 1 ]] && sed -n "$((n - 1))p" "$f")
    [[ $prev == *"sec-ok:"* ]] && continue
    hits+="$f:$n: $rest"$'\n'
  done < <(grep -nE "$re" "$@" /dev/null 2>/dev/null)
  if [[ -n $hits ]]; then
    printf '\nFAIL: %s\n%s' "$label" "$hits"
    fail=1
  fi
}

flag "eval is banned in QML" '(^|[^a-zA-Z_.-])eval[ (]' "${qml[@]}"
flag "QML concatenates into a bash -c body (pass values as positional args)" '"-(l)?c",.*\+' "${qml[@]}"

if [[ $fail == 0 ]]; then
  echo "orbital security-check: OK"
else
  echo "orbital security-check: FAILED"
fi
exit $fail
