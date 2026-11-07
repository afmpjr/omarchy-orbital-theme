#!/usr/bin/env bash
# Node unit test of the notification center model and i18n dictionary.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== Running notifications Model & I18n Tests (English Default) ==="
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 node test/notifications-model-test.js

echo "=== Running notifications Model & I18n Tests (LANG=C Fallback) ==="
LANG=C LC_ALL=C node test/notifications-model-test.js

echo "=== Running notifications Model & I18n Tests (LANG=pt_BR.UTF-8) ==="
LANG=pt_BR.UTF-8 LC_ALL=pt_BR.UTF-8 node test/notifications-model-test.js

echo "=== notifications Model & I18n Tests Complete ==="
