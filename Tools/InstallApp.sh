#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

[[ $# -eq 2 ]] || { print -u2 'Usage: InstallApp.sh SOURCE_APP DESTINATION_APP'; exit 2; }
SOURCE="${1:a}"
DESTINATION="${2:a}"
PROCESS_PATTERN="^$(print -r -- "$DESTINATION/Contents/MacOS/PlainTranslate" | sed 's/[][\\.^$*+?(){}|]/\\&/g')($| )"

check_destination() {
  [[ ! -L "$DESTINATION" ]] || { print -u2 'Refusing to replace a symbolic link.'; return 1; }
  if [[ -e "$DESTINATION" ]]; then
    local existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist" 2>/dev/null || true)"
    [[ "$existing_id" == 'com.chyo.plaintranslate' ]] || {
      print -u2 'Refusing to replace an application with a different identity.'; return 1
    }
  fi
  if pgrep -f "$PROCESS_PATTERN" >/dev/null; then
    print -u2 'Quit PlainTranslate before installing this update.'; return 1
  else
    [[ $? -eq 1 ]] || { print -u2 'Could not check whether PlainTranslate is running.'; return 1; }
  fi
}

check_destination || exit 1
# The stage and backup share the destination volume, so each move is a rename.
WORK="$(mktemp -d "${DESTINATION:h}/.PlainTranslate.install.XXXXXX")"
STAGED="$WORK/Staged.app"
BACKUP="$WORK/Previous.app"
HAD_DESTINATION=false
SWAPPING=false
COMPLETE=false

cleanup() {
  local result=$?
  trap - EXIT
  trap '' HUP INT TERM
  if ! $COMPLETE && $SWAPPING; then
    if [[ -e "$BACKUP" ]]; then
      if [[ -e "$DESTINATION" || -L "$DESTINATION" ]]; then
        if ! mv -- "$DESTINATION" "$WORK/Failed.app"; then
          print -u2 "Could not remove the failed update. Previous app retained at: $BACKUP"
          exit 1
        fi
      fi
      if ! mv -- "$BACKUP" "$DESTINATION"; then
        print -u2 "Could not restore the previous app. Backup retained at: $BACKUP"
        exit 1
      fi
    elif ! $HAD_DESTINATION && [[ ! -e "$STAGED" ]]; then
      rm -rf -- "$DESTINATION"
    fi
  fi
  rm -rf -- "$WORK"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

ditto "$SOURCE" "$STAGED"
STAGED_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$STAGED/Contents/Info.plist" 2>/dev/null || true)"
[[ "$STAGED_ID" == 'com.chyo.plaintranslate' ]] || {
  print -u2 'Refusing to install an application with a different identity.'; exit 1
}
codesign --verify --deep --strict "$STAGED"
check_destination || exit 1
[[ ! -e "$DESTINATION" ]] || HAD_DESTINATION=true
SWAPPING=true
if $HAD_DESTINATION; then mv -- "$DESTINATION" "$BACKUP"; fi
mv -- "$STAGED" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
COMPLETE=true
print "Installed: $DESTINATION"
