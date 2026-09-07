#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_xcode
mkdir -p "$PET_BUILD_ROOT/tools"
xcrun swiftc -O "$PET_ROOT/Sources/PetDefinition.swift" "$PET_ROOT/Sources/EyeTracking.swift" \
  "$PET_ROOT/Sources/PetView.swift" "$PET_ROOT/scripts/ValidatePet/main.swift" \
  -o "$PET_BUILD_ROOT/tools/validate-pet"
"$PET_BUILD_ROOT/tools/validate-pet" "${1:-$PET_ROOT/Resources}"
