#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT="${0:A:h:h}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/plaintranslate-install-tests.XXXXXX")"
WORK="${WORK:a}"
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/Applications [test]+ with spaces"
export TEST_DESTINATION="$WORK/Applications [test]+ with spaces/PlainTranslate.app"
export TEST_STATE="$WORK/state"
SOURCE="$WORK/Source with spaces.app"
SNAPSHOT="$WORK/Previous snapshot.app"

# Fake only external operations; all app bytes and renames stay in this fixture.
cat > "$WORK/bin/ditto" <<'SH'
#!/bin/zsh
set -euo pipefail
if [[ "$TEST_MODE" == copy-failure ]]; then
  mkdir -p "$2/Contents"
  cp "$1/Contents/Info.plist" "$2/Contents/Info.plist"
  exit 1
fi
exec /usr/bin/ditto "$@"
SH
cat > "$WORK/bin/codesign" <<'SH'
#!/bin/zsh
set -euo pipefail
[[ $# -eq 4 && "$1" == --verify && "$2" == --deep && "$3" == --strict ]]
app="${argv[-1]}"
[[ "$(<"$app/Contents/signature")" == valid ]]
if [[ "$app" == "$TEST_DESTINATION" ]]; then
  [[ "$TEST_MODE" != verify-installed && "$TEST_MODE" != rollback-failure ]]
else
  [[ "$TEST_MODE" != verify-stage ]]
  touch "$TEST_STATE/stage-verified"
fi
SH
cat > "$WORK/bin/pgrep" <<'SH'
#!/bin/zsh
set -euo pipefail
[[ $# -eq 2 && "$1" == -f ]]
# Check regex escaping, including the spaces and metacharacters in this path.
[[ "$TEST_DESTINATION/Contents/MacOS/PlainTranslate" =~ "$2" ]] || exit 2
[[ "$TEST_DESTINATION/Contents/MacOS/PlainTranslate --argument" =~ "$2" ]] || exit 2
if [[ "$TEST_MODE" == running || ( "$TEST_MODE" == running-after-stage && -f "$TEST_STATE/stage-verified" ) ]]; then exit 0; fi
if [[ "$TEST_MODE" == process-check-failure ]]; then exit 2; fi
exit 1
SH
cat > "$WORK/bin/mv" <<'SH'
#!/bin/zsh
set -euo pipefail
[[ "$1" != -- ]] || shift
if [[ "$1" == "$TEST_DESTINATION" && "$2" == */Previous.app ]]; then
  [[ "$TEST_MODE" != backup-failure ]] || exit 1
  /bin/mv "$@"
  if [[ "$TEST_MODE" == signal-backup-* ]]; then kill -"${TEST_MODE##signal-backup-}" "$PPID"; fi
elif [[ "$1" == */Staged.app && "$2" == "$TEST_DESTINATION" ]]; then
  [[ -f "$TEST_STATE/stage-verified" ]]
  [[ "$TEST_MODE" != swap-failure ]] || exit 1
  /bin/mv "$@"
  [[ "$TEST_MODE" != swap-after-failure ]] || exit 1
  if [[ "$TEST_MODE" == signal-new-* ]]; then kill -"${TEST_MODE##signal-new-}" "$PPID"; fi
elif [[ "$1" == */Previous.app && "$TEST_MODE" == rollback-failure ]]; then
  exit 1
else
  exec /bin/mv "$@"
fi
SH
chmod +x "$WORK/bin/ditto" "$WORK/bin/codesign" "$WORK/bin/pgrep" "$WORK/bin/mv"
export PATH="$WORK/bin:$PATH"
export TEST_MODE=success

make_app() {
  local app="$1" payload="$2" identity="${3:-com.chyo.plaintranslate}"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>$identity</string></dict></plist>
EOF
  print -r -- "$payload" > "$app/Contents/MacOS/PlainTranslate"
  print -r -- "resource $payload" > "$app/Contents/Resources/payload"
  print valid > "$app/Contents/signature"
}

reset_fixture() {
  rm -rf -- "$TEST_DESTINATION" "$TEST_STATE" "$SNAPSHOT"
  mkdir -p "$TEST_STATE"
  make_app "$TEST_DESTINATION" old
  /usr/bin/ditto "$TEST_DESTINATION" "$SNAPSHOT"
}

assert_clean() {
  local leftovers=("${TEST_DESTINATION:h}"/.PlainTranslate.install.*(N))
  [[ ${#leftovers} -eq 0 ]] || { print -u2 "Transaction directory leaked: $TEST_MODE"; exit 1; }
}

expect_failure() {
  if "$ROOT/Tools/InstallApp.sh" "$SOURCE" "$TEST_DESTINATION" >"$WORK/output" 2>&1; then
    print -u2 "Expected install failure: $TEST_MODE"
    exit 1
  fi
}

make_app "$SOURCE" new
reset_fixture
"$ROOT/Tools/InstallApp.sh" "$SOURCE" "$TEST_DESTINATION" >"$WORK/output" 2>&1
diff -r "$SOURCE" "$TEST_DESTINATION"
assert_clean
rm -rf -- "$TEST_DESTINATION"
"$ROOT/Tools/InstallApp.sh" "$SOURCE" "$TEST_DESTINATION" >"$WORK/output" 2>&1
diff -r "$SOURCE" "$TEST_DESTINATION"
assert_clean

for TEST_MODE in copy-failure verify-stage backup-failure swap-failure swap-after-failure verify-installed signal-backup-TERM signal-new-TERM signal-new-HUP signal-new-INT running running-after-stage process-check-failure; do
  reset_fixture
  expect_failure
  diff -r "$SNAPSHOT" "$TEST_DESTINATION"
  assert_clean
done

for TEST_MODE in copy-failure verify-stage swap-failure swap-after-failure verify-installed signal-new-TERM signal-new-HUP signal-new-INT; do
  reset_fixture
  rm -rf -- "$TEST_DESTINATION"
  expect_failure
  [[ ! -e "$TEST_DESTINATION" && ! -L "$TEST_DESTINATION" ]]
  assert_clean
done

TEST_MODE=success
reset_fixture
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.example.unrelated' "$TEST_DESTINATION/Contents/Info.plist"
/usr/bin/ditto "$TEST_DESTINATION" "$SNAPSHOT"
expect_failure
diff -r "$SNAPSHOT" "$TEST_DESTINATION"
assert_clean

reset_fixture
rm -rf -- "$TEST_DESTINATION"
ln -s "$SNAPSHOT" "$TEST_DESTINATION"
expect_failure
[[ -L "$TEST_DESTINATION" && "$(readlink "$TEST_DESTINATION")" == "$SNAPSHOT" ]]
[[ "$(<"$SNAPSHOT/Contents/MacOS/PlainTranslate")" == old ]]
assert_clean

reset_fixture
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.example.unrelated' "$SOURCE/Contents/Info.plist"
expect_failure
diff -r "$SNAPSHOT" "$TEST_DESTINATION"
assert_clean
rm -rf -- "$TEST_DESTINATION"
expect_failure
[[ ! -e "$TEST_DESTINATION" ]]
assert_clean
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.chyo.plaintranslate' "$SOURCE/Contents/Info.plist"

TEST_MODE=rollback-failure
reset_fixture
expect_failure
backups=("${TEST_DESTINATION:h}"/.PlainTranslate.install.*/Previous.app(N))
[[ ${#backups} -eq 1 ]]
diff -r "$SNAPSHOT" "$backups[1]"
[[ "$(<"$WORK/output")" == *"Backup retained at: $backups[1]"* ]]
print 'Installer fixture tests passed (success, refusals, copy/verify/rename failures, signals, rollback backup retention).'
