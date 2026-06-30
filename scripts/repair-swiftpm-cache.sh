#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_PATH="${COLEARNER_SWIFT_SCRATCH_PATH:-$HOME/Library/Caches/CoLearner/swiftpm-build}"

cd "$ROOT_DIR"

needs_warm_build=0

if [[ -L .build ]]; then
  current_target="$(readlink .build)"
  if [[ "$current_target" == "$SCRATCH_PATH" ]]; then
    mkdir -p "$SCRATCH_PATH"
    needs_warm_build=1
  else
    rm -f .build
    mkdir -p "$SCRATCH_PATH"
    ln -s "$SCRATCH_PATH" .build
    needs_warm_build=1
  fi
else
  rm -rf .build
  mkdir -p "$SCRATCH_PATH"
  ln -s "$SCRATCH_PATH" .build
  needs_warm_build=1
fi

if [[ "$needs_warm_build" -eq 1 ]]; then
  swift build --scratch-path "$ROOT_DIR/.build" >/dev/null
fi

printf 'SwiftPM build cache repaired: .build -> %s\n' "$SCRATCH_PATH"
