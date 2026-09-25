#!/usr/bin/env bash
# Every tr("...") string in the plugins must have a Portuguese entry in plugins/orbital.ui/I18n.js,
# and every entry must be used (so the dictionary never drifts from the interface).
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import glob, re, sys
dic = open("plugins/orbital.ui/I18n.js", encoding="utf-8").read()
keys = set(re.findall(r'"((?:[^"\\]|\\.)*)"\s*:', dic))
norm = lambda s: s.encode().decode("unicode_escape").encode("latin-1", "backslashreplace").decode("unicode_escape") if "\\u" in s else s
used = set()
for f in glob.glob("plugins/orbital.*/*.qml"):
    for m in re.findall(r'\btr\("((?:[^"\\]|\\.)*)"\)', open(f, encoding="utf-8").read()):
        used.add(m.replace("\\u203A", "›").replace("\\u2039", "‹").replace("\\u2026", "…"))
missing = sorted(used - keys); unused = sorted(keys - used)
for m in missing: print("FAIL - no Portuguese entry for:", m)
for u in unused: print("FAIL - unused dictionary entry:", u)
if missing or unused: sys.exit(1)
print(f"ok   - {len(used)} interface strings, all translated, none unused")
PY
