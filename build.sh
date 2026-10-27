#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT="${0:A:h}"
cd "$ROOT"
INSTALL=false
[[ $# -le 1 ]] || { print -u2 'Pass only one option.'; exit 2; }
case "${1:-}" in
  "") ;;
  --install) INSTALL=true ;;
  --test) exec swift test ;;
  *) print -u2 'Usage: ./build.sh [--test | --install]'; exit 2 ;;
esac

swift build -c release --product PlainTranslate
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p "$ROOT/build"
STAGE="$(mktemp -d "$ROOT/build/.stage.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
APP="$STAGE/PlainTranslate.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PlainTranslate" "$APP/Contents/MacOS/PlainTranslate"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp NOTICE.md "$APP/Contents/Resources/NOTICE.txt"
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  COMMIT="$(git rev-parse --short=12 HEAD)"
  if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    COMMIT+="-dirty"
  fi
  /usr/libexec/PlistBuddy -c "Add :PlainTranslateCommit string $COMMIT" "$APP/Contents/Info.plist"
fi
swift -module-cache-path "$ROOT/.build/icon-module-cache" Tools/MakeIcon.swift "$STAGE/AppIcon.iconset"
iconutil -c icns "$STAGE/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
SIGNING_IDENTITY="${PLAINTRANSLATE_SIGNING_IDENTITY:--}"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
rm -rf -- "$ROOT/build/PlainTranslate.app"
mv "$APP" "$ROOT/build/PlainTranslate.app"
print "Built: $ROOT/build/PlainTranslate.app"

if $INSTALL; then
  DESTINATION='/Applications/PlainTranslate.app'
  if [[ -L "$DESTINATION" ]]; then
    print -u2 'Refusing to replace a symbolic link in /Applications.'; exit 1
  fi
  if [[ -e "$DESTINATION" ]]; then
    EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist" 2>/dev/null || true)"
    [[ "$EXISTING_ID" == 'com.chyo.plaintranslate' ]] || {
      print -u2 'Refusing to replace an application with a different identity.'; exit 1
    }
    if pgrep -f '^/Applications/PlainTranslate.app/Contents/MacOS/PlainTranslate($| )' >/dev/null; then
      print -u2 'Quit PlainTranslate before installing this update.'; exit 1
    fi
    rm -rf -- "$DESTINATION"
  fi
  ditto "$ROOT/build/PlainTranslate.app" "$DESTINATION"
  codesign --verify --deep --strict "$DESTINATION"
  print "Installed: $DESTINATION"
fi
