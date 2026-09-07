#!/bin/bash
set -euo pipefail
PET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PET_CHECKOUT_ID="$(printf '%s' "$PET_ROOT" | shasum | cut -c 1-12)"
PET_BUILD_ROOT="${PET_BUILD_ROOT:-$HOME/Library/Developer/Xcode/DerivedData/BEXAIPetTerminal-$PET_CHECKOUT_ID}"
PET_DERIVED_DATA="$PET_BUILD_ROOT/DerivedData"
PET_PRODUCT="Pet Terminal"
PET_SCHEME="PetTerminal"
# Shared with the build, install, and package entry points that source this file.
# shellcheck disable=SC2034
PET_APP="$PET_DERIVED_DATA/Build/Products/Release/$PET_PRODUCT.app"

require_xcode() {
  if [[ "$(uname -s)" != Darwin ]] || ! xcodebuild -version >/dev/null 2>&1; then
    printf '%s\n' 'Build on a Mac with full Xcode 26.1 or newer installed and selected.' >&2
    printf '%s\n' 'Open Xcode once to finish setup. Command Line Tools alone are insufficient.' >&2
    exit 1
  fi
  mkdir -p "$PET_BUILD_ROOT/logs"
}

run_xcode() {
  local action="$1" configuration="$2" log="$PET_BUILD_ROOT/logs/$1-$2.log"
  printf '%s\n' "$action ($configuration)…"
  if ! xcodebuild -project "$PET_ROOT/PetTerminal.xcodeproj" -scheme "$PET_SCHEME" \
      -configuration "$configuration" -derivedDataPath "$PET_DERIVED_DATA" \
      -destination "platform=macOS,arch=$(uname -m)" "$action" >"$log" 2>&1; then
    tail -n 80 "$log" >&2
    printf 'Full log: %s\n' "$log" >&2
    return 1
  fi
  printf 'Succeeded. Log: %s\n' "$log"
}
