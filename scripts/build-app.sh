#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_PATH="${COLEARNER_SWIFT_SCRATCH_PATH:-/tmp/CoLearner-build}"
APP_PATH="${COLEARNER_APP_PATH:-/tmp/CoLearner.app}"
EXECUTABLE_PATH="$SCRATCH_PATH/arm64-apple-macosx/debug/CoLearner"

cd "$ROOT_DIR"
swift build --scratch-path "$SCRATCH_PATH" >&2

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
cp "$EXECUTABLE_PATH" "$APP_PATH/Contents/MacOS/CoLearner"
chmod +x "$APP_PATH/Contents/MacOS/CoLearner"

cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>CoLearner</string>
  <key>CFBundleIdentifier</key>
  <string>dev.pnkjsng.CoLearner</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>CoLearner</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_PATH"
