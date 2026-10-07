#!/usr/bin/env bash
# Static contract for the destructive dock-pins flow: reset asks first through
# OrbitalDialog (Cancel is the default, dismiss never applies), the pins are
# snapshotted before removal, and restore is only offered while a backup exists.
# No shell, no display: pure source assertions, same pattern as
# scripts/test-settings-keyboard.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
from pathlib import Path

settings = Path("plugins/orbital.settings/Settings.qml").read_text(encoding="utf-8")
dialog = Path("plugins/orbital.ui/OrbitalDialog.qml").read_text(encoding="utf-8")
change = Path("plugins/orbital.settings/orbital-settings-change").read_text(encoding="utf-8")
state = Path("plugins/orbital.settings/orbital-settings-state").read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL - {message}")
    print(f"ok   - {message}")


require("OrbitalUi.OrbitalDialog" in settings, "reset uses the shared OrbitalDialog")
require('tone: "danger"' in settings, "reset dialog is marked dangerous")
require('title: "Reset dock pins?"' in settings, "reset dialog names the consequence")
require('{ id: "cancel"' in settings and '{ id: "reset"' in settings,
        "reset dialog offers Cancel and Reset pins")
require("defaultButton: 0" in settings, "Cancel is the default (Enter-safe) button")
require("onDismissed: root.confirmResetPins = false" in settings,
        "dismissing (Esc, outside click) applies nothing")
require('if (id === "reset") root.setPreference("reset-pins", "true")' in settings,
        "only an explicit Reset sends reset-pins")

reset_row = settings[settings.index('label: "Reset dock pins"'):settings.index('label: "Restore dock pins"')]
require("root.confirmResetPins = true" in reset_row, "reset row opens the dialog")
require('setPreference("reset-pins"' not in reset_row, "reset row never applies directly")

restore_at = settings.index('label: "Restore dock pins"')
restore_row = settings[restore_at:settings.index("}", settings.index("onActivated", restore_at)) + 1]
require("visible: root.pPinsBackup" in restore_row, "restore row shows only while a backup exists")
require('setPreference("restore-pins", "true")' in restore_row, "restore row restores the snapshot")
require("root.pPinsBackup = state.pinsBackup === true" in settings,
        "panel learns the backup state when settings load")

require("cp -a " in change and ".bak" in change, "reset snapshots the pins before removing them")
require("restore-pins)" in change, "change script restores the snapshot on demand")
require("no saved pins to restore" in change, "restore without a backup fails loudly")
require('"pinsBackup"' in state, "settings state reports whether a backup exists")

for key in ("Qt.Key_Escape", "Qt.Key_Return", "Qt.Key_Enter", "Qt.Key_Tab"):
    require(key in dialog, f"dialog answers {key} without a mouse")
PY
