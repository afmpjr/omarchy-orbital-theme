#!/usr/bin/env bash
# Verify the account panel's icon resolution end to end.
#
# Instruments Account.qml so the guest's QML engine writes what iconSource()
# returns for every panel icon into /tmp/acc-diag.txt, then deploys, restarts
# the shell, opens the panel and prints the report. Reverts the instrumentation
# afterwards so nothing temporary is left in the working tree.
#
# Usage: scripts/verify-account-icons.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TB="${TB:-/mnt/dados/projects/omarchy-testbed/scripts/tb}"
# Absolute guest path: $HOME here is the *host* home, and tb ssh runs commands in
# a single non-interactive shell, so a leading ~ would not be expanded remotely.
GUEST="/home/tester/.config/omarchy/plugins"

cleanup() {
  echo "--- reverting instrumentation ---"
  (cd "$REPO" && python3 scripts/verify-account-icons.py revert) || true
}
trap cleanup EXIT

echo "--- instrumenting Account.qml ---"
(cd "$REPO" && python3 scripts/verify-account-icons.py install) || exit 1

echo "--- deploying to guest ---"
for f in orbital.ui/OrbitalIcons.qml orbital.ui/qmldir orbital.account/Account.qml; do
  "$TB" ssh "mkdir -p $GUEST/$(dirname "$f")" || exit 1
  base64 -w0 "$REPO/plugins/$f" | "$TB" ssh "base64 -d > $GUEST/$f" || exit 1
done
echo "deployed"

echo "--- restarting shell and opening panel ---"
"$TB" ssh 'export OMARCHY_PATH=/usr/share/omarchy XDG_RUNTIME_DIR=/run/user/1000
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr | head -1)
rm -f /tmp/acc-diag.txt
omarchy restart shell >/dev/null 2>&1
sleep 22
omarchy-shell shell toggle orbital.account "{}" >/dev/null 2>&1
sleep 8
echo "=== report ==="
cat /tmp/acc-diag.txt 2>/dev/null || echo "(nothing written)"' 2>&1 | sed "s|$GUEST|~/plugins|g"

echo "--- QML errors during that window ---"
"$TB" ssh 'export XDG_RUNTIME_DIR=/run/user/1000
journalctl --user -t omarchy-shell -b --no-pager --since "-40s" 2>/dev/null \
  | grep -iE "OrbitalIcons|Account\.qml" | tail -6' || true
