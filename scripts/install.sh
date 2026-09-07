#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
destination="$HOME/Applications"
launch=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination) [[ $# -ge 2 ]] || { printf '%s\n' 'Missing destination.' >&2; exit 2; }; destination="$2"; shift 2 ;;
    --open) launch=true; shift ;;
    *) printf '%s\n' 'Usage: ./scripts/install.sh [--destination DIRECTORY] [--open]' >&2; exit 2 ;;
  esac
done
"$PET_ROOT/scripts/build.sh"
if pgrep -x "$PET_PRODUCT" >/dev/null; then
  printf '%s\n' 'Pet Terminal is running. Save your terminal work and quit Pet Terminal before installing.' >&2
  printf '%s\n' 'The installer does not close any app, shell, or other terminal for you.' >&2
  exit 1
fi
mkdir -p "$destination"
destination="$(cd "$destination" && pwd)"
target="$destination/$PET_PRODUCT.app"
stage="$(mktemp -d "$destination/.pet-install.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto --norsrc --noextattr --noqtn "$PET_APP" "$stage/$PET_PRODUCT.app"
codesign --verify --deep --strict "$stage/$PET_PRODUCT.app"
backup=""
if [[ -e "$target" ]]; then
  expected="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PET_APP/Contents/Info.plist")"
  actual="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$actual" == "$expected" ]] || { printf '%s\n' 'An unrelated app uses this name. Choose another destination.' >&2; exit 1; }
  mkdir -p "$PET_BUILD_ROOT/backups"
  backup="$(mktemp -d "$PET_BUILD_ROOT/backups/install.XXXXXX")/$PET_PRODUCT.app"
  mv "$target" "$backup"
fi
if ! mv "$stage/$PET_PRODUCT.app" "$target"; then
  [[ -z "$backup" ]] || mv "$backup" "$target"
  exit 1
fi
printf 'Installed: %s\n' "$target"
if [[ "$launch" == true ]]; then open "$target"; fi
