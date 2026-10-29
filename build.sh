#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT="${0:A:h}"
cd "$ROOT"
INSTALL=false
TEST=false
[[ $# -le 1 ]] || { print -u2 'Pass only one option.'; exit 2; }
case "${1:-}" in
  "") ;;
  --install) INSTALL=true ;;
  --test) TEST=true ;;
  *) print -u2 'Usage: ./build.sh [--test | --install]'; exit 2 ;;
esac

MACOS_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
MACOS_SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
APP_MINIMUM_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
# SwiftPM can stamp the deployment target as the SDK, enabling legacy controls.
SDK_FLAGS=(--sdk "$MACOS_SDK_PATH" -Xlinker -platform_version -Xlinker macos -Xlinker "$APP_MINIMUM_MACOS" -Xlinker "$MACOS_SDK_VERSION")
if $TEST; then exec swift test "${SDK_FLAGS[@]}"; fi

SIGNING_CONFIG="$ROOT/.local-signing-identity"
if [[ -n "${PLAINTRANSLATE_SIGNING_IDENTITY:-}" ]]; then
  SIGNING_IDENTITY="$PLAINTRANSLATE_SIGNING_IDENTITY"
elif [[ -e "$SIGNING_CONFIG" || -L "$SIGNING_CONFIG" ]]; then
  [[ -f "$SIGNING_CONFIG" && ! -L "$SIGNING_CONFIG" ]] || { print -u2 'Invalid local signing configuration.'; exit 1; }
  SIGNING_IDENTITY="$(<"$SIGNING_CONFIG")"
  [[ "$SIGNING_IDENTITY" =~ '^[[:xdigit:]]{40}$' ]] || { print -u2 'Invalid local signing certificate fingerprint.'; exit 1; }
else
  SIGNING_IDENTITY='-'
  print -u2 'Ad-hoc signing: run ./Tools/SetupLocalSigning.sh once to preserve local Accessibility identity across updates.'
fi

swift build "${SDK_FLAGS[@]}" -c release --product PlainTranslate
BIN_DIR="$(swift build "${SDK_FLAGS[@]}" -c release --show-bin-path)"
mkdir -p "$ROOT/build"
STAGE="$(mktemp -d "$ROOT/build/.stage.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
APP="$STAGE/PlainTranslate.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PlainTranslate" "$APP/Contents/MacOS/PlainTranslate"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp NOTICE.md "$APP/Contents/Resources/NOTICE.txt"
cp Resources/Brand/BrandMarkTemplate.png Resources/Brand/BrandMarkTemplate@2x.png "$APP/Contents/Resources/"
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  COMMIT="$(git rev-parse --short=12 HEAD)"
  if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    COMMIT+="-dirty"
  fi
  /usr/libexec/PlistBuddy -c "Add :PlainTranslateCommit string $COMMIT" "$APP/Contents/Info.plist"
fi
swift -module-cache-path "$ROOT/.build/icon-module-cache" Tools/MakeIcon.swift Resources/Brand/AppIcon.png "$STAGE/AppIcon.iconset"
iconutil -c icns "$STAGE/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
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
