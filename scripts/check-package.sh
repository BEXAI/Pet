#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
bundle="${1:-$PET_APP}"
[[ -d "$bundle/Contents" ]] || { printf '%s\n' 'Provide a built app bundle.' >&2; exit 2; }

# Inspect raw bytes, including every architecture in a universal executable.
# Debug symbols and compiler metadata can otherwise disclose the builder's paths.
status=0
while IFS= read -r -d '' artifact; do
  if LC_ALL=C grep -aFq -e "$HOME/" -e "$PET_ROOT/" -e "$PET_BUILD_ROOT/" "$artifact"; then
    printf 'Private build path detected in: %s\n' "${artifact#"$bundle/"}" >&2
    status=1
  fi
done < <(find "$bundle/Contents" -type f -print0)
if [[ "$status" -ne 0 ]]; then
  printf '%s\n' 'Do not distribute this bundle. Remove embedded build paths and rebuild.' >&2
  exit "$status"
fi
printf '%s\n' 'Package path check passed: no builder home, checkout, or build directory found.'
