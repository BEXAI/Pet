#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
"$PET_ROOT/scripts/build.sh"
mkdir -p "$PET_ROOT/dist"
archive="$PET_ROOT/dist/Pet-Terminal-macOS.zip"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$PET_APP" "$archive"
printf 'Packaged: %s\n' "$archive"
printf '%s\n' 'This build is ad-hoc signed for local use, not Developer ID signed or notarized.'
