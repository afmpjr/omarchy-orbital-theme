#!/usr/bin/env bash
# Node unit test of the notification center's history math (needs node; the widget itself does not).
set -euo pipefail
cd "$(dirname "$0")/.."
node test/notifications-model-test.js
