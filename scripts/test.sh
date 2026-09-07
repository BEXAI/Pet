#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_xcode
"$PET_ROOT/scripts/validate.sh"
run_xcode test Debug
