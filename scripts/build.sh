#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_xcode
"$PET_ROOT/scripts/validate.sh"
run_xcode build Release
codesign --verify --deep --strict "$PET_APP"
printf 'Built app: %s\n' "$PET_APP"
