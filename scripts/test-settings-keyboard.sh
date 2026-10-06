#!/usr/bin/env bash
# Check that every custom settings control participates in keyboard navigation.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
from pathlib import Path

source = Path("plugins/orbital.settings/Settings.qml").read_text(encoding="utf-8")

def component(name):
    marker = f"component {name}:"
    start = source.index(marker)
    next_component = source.find("\n  component ", start + len(marker))
    return source[start: next_component if next_component >= 0 else len(source)]

def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL - {message}")
    print(f"ok   - {message}")

for name in ("SideRow", "OptionRow", "SwatchButton", "ThumbButton"):
    body = component(name)
    require("activeFocusOnTab: true" in body, f"{name} is reachable with Tab")
    require("Keys.onPressed" in body, f"{name} handles keyboard input")
    require("Qt.Key_Space" in body and "Qt.Key_Return" in body and "Qt.Key_Enter" in body,
            f"{name} activates with Space, Return and Enter")
    require("activeFocus ?" in body, f"{name} shows a visible focus indicator")

require("function moveKeyboardFocus(current, forward)" in source and "nextItemInFocusChain(forward)" in source,
        "arrow navigation follows the visible focus chain")
require("function focusSection(index)" in source and "Qt.Key_Up" in component("SideRow")
        and "Qt.Key_Down" in component("SideRow"), "Up and Down navigate settings sections")
require("activeFocusOnTab: true" in source[source.index("id: hexInput"):source.index("onEditingFinished: root.applyCustomHex")],
        "custom accent input is reachable with Tab")
require("activeFocusOnTab: true" in source[source.index("id: avatarPathInput"):source.index("onTextChanged: root.pAvatarPath")],
        "avatar path input is reachable with Tab")
for identifier in ("closeButton", "applyButton"):
    start = source.index(f"id: {identifier}")
    end = source.find("\n          }", start)
    body = source[start:end]
    require("activeFocusOnTab: true" in body and "Qt.Key_Space" in body and "Qt.Key_Return" in body,
            f"{identifier} is keyboard accessible")
PY
