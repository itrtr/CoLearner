#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
APP_PATH="$(scripts/build-app.sh | tail -n 1)"
exec "$APP_PATH/Contents/MacOS/CoLearner"
