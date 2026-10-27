#!/usr/bin/env bash
# scripts/test-doctor-model.sh
# Deterministic unit test runner for omarchy-doctor widget model (DoctorModel.js).
# Validates against canonical fixtures from Patricia's QA Matrix.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Running omarchy-doctor Model Unit Tests ==="
cd "$ROOT_DIR"
node test/doctor-model-test.js
echo "=== omarchy-doctor Model Unit Tests Complete ==="
