#!/usr/bin/env bash
# scripts/test-doctor-model.sh
# Deterministic unit test runner for omarchy-doctor widget model (DoctorModel.js).
# Validates English default + PT-BR locale switching against canonical fixtures.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Running omarchy-doctor Model Unit Tests (English Default en_US.UTF-8) ==="
cd "$ROOT_DIR"
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 node test/doctor-model-test.js

echo "=== Running omarchy-doctor Model Unit Tests (LANG=C fallback) ==="
LANG=C LC_ALL=C node test/doctor-model-test.js

echo "=== Running omarchy-doctor Model Unit Tests (LANG=pt_BR.UTF-8 localized) ==="
LANG=pt_BR.UTF-8 LC_ALL=pt_BR.UTF-8 node test/doctor-model-test.js

echo "=== omarchy-doctor Model Unit Tests Complete ==="
