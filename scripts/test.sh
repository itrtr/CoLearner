#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_PATH="${COLEARNER_SWIFT_TEST_SCRATCH_PATH:-/tmp/CoLearner-test-build}"

cd "$ROOT_DIR"
swift test --scratch-path "$SCRATCH_PATH"
