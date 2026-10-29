#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
umask 077

[[ $# -eq 0 ]] || { print -u2 'Usage: ./Tools/SetupLocalSigning.sh'; exit 2; }
ROOT="${0:A:h:h}"
CONFIG="$ROOT/.local-signing-identity"
NAME='PlainTranslate Local Development'
[[ ! -L "$CONFIG" ]] || { print -u2 'Refusing a symbolic-link signing configuration.'; exit 1; }
[[ ! -e "$CONFIG" || -f "$CONFIG" ]] || { print -u2 'Signing configuration must be a regular file.'; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/plaintranslate-signing.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

if [[ -f "$CONFIG" ]]; then
  IDENTITY="$(<"$CONFIG")"
else
  # Self-signed identities are usable by codesign even without a trusted root.
  IDENTITIES=(${(f)"$(/usr/bin/security find-identity -p codesigning | awk -v name="$NAME" 'index($0, "\"" name "\"") {print $2}' | sort -u)"})
  if (( ${#IDENTITIES} > 1 )); then
    print -u2 'Multiple PlainTranslate local identities found; choose one explicitly instead of creating another.'
    exit 1
  elif (( ${#IDENTITIES} == 1 )); then
    IDENTITY="$IDENTITIES[1]"
  else
    if /usr/bin/security find-certificate -c "$NAME" >/dev/null 2>&1; then
      print -u2 'PlainTranslate certificate exists without a usable private key. Restore that identity; do not replace it automatically.'
      exit 1
    fi
    KEYCHAIN="$(/usr/bin/security default-keychain -d user | sed -E 's/^[[:space:]]*"(.*)"[[:space:]]*$/\1/')"
    [[ -f "$KEYCHAIN" ]] || { print -u2 'An existing default user Keychain is required.'; exit 1; }
    /usr/bin/openssl req -new -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 \
      -subj "/CN=$NAME/" \
      -addext 'basicConstraints=critical,CA:FALSE' \
      -addext 'keyUsage=critical,digitalSignature' \
      -addext 'extendedKeyUsage=critical,codeSigning' \
      -keyout "$WORK/private.pem" -out "$WORK/certificate.pem" 2>"$WORK/generation.log"
    IDENTITY="$(/usr/bin/openssl x509 -in "$WORK/certificate.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
    cat "$WORK/certificate.pem" "$WORK/private.pem" > "$WORK/identity.pem"
    # Import only this new key, non-extractable and restricted to codesign.
    /usr/bin/security import "$WORK/identity.pem" -k "$KEYCHAIN" -f pemseq -t agg -x -T /usr/bin/codesign
    rm -f -- "$WORK/private.pem" "$WORK/identity.pem"
  fi
fi
[[ "$IDENTITY" =~ '^[[:xdigit:]]{40}$' ]] || { print -u2 'Invalid signing certificate fingerprint.'; exit 1; }

# A changed payload must still satisfy exactly the same certificate-bound identity.
for VERSION in 1 2; do
  APP="$WORK/Probe$VERSION.app"
  mkdir -p "$APP/Contents/MacOS"
  cp /bin/echo "$APP/Contents/MacOS/SigningProbe"
  cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.chyo.plaintranslate.signing-probe</string>
<key>CFBundleExecutable</key><string>SigningProbe</string>
<key>CFBundleVersion</key><string>$VERSION</string>
</dict></plist>
EOF
  /usr/bin/codesign --force --sign "$IDENTITY" --options runtime --timestamp=none "$APP"
  /usr/bin/codesign --verify --strict "$APP"
  /usr/bin/codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p' > "$WORK/requirement$VERSION"
  /usr/bin/codesign -dvvv "$APP" 2>&1 | sed -n 's/^CDHash=//p' > "$WORK/hash$VERSION"
done
REQUIREMENT="$(<"$WORK/requirement1")"
[[ "$REQUIREMENT" == *certificate* && "$REQUIREMENT" != *cdhash* ]] || { print -u2 'Signing identity is not certificate-bound.'; exit 1; }
cmp -s "$WORK/requirement1" "$WORK/requirement2" || { print -u2 'Signing requirement changed between test updates.'; exit 1; }
[[ -s "$WORK/hash1" && -s "$WORK/hash2" ]] || { print -u2 'Missing signed test hashes.'; exit 1; }
if cmp -s "$WORK/hash1" "$WORK/hash2"; then
  print -u2 'Test payloads did not produce different code hashes.'
  exit 1
fi
/usr/bin/codesign --verify --strict -R="$REQUIREMENT" "$WORK/Probe2.app"
if [[ ! -f "$CONFIG" ]]; then
  print -r -- "$IDENTITY" > "$WORK/fingerprint"
  mv "$WORK/fingerprint" "$CONFIG"
fi
print 'Stable local signing configured; changed-payload identity check passed.'
print 'Future builds in this checkout will reuse this certificate. Keep its private key in your Keychain.'
