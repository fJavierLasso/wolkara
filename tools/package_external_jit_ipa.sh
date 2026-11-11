#!/usr/bin/env bash
# Build an experimental, ad-hoc-signed Wolkara External JIT IPA.
# This app needs a separate, device-signed development profile at install time;
# compiling an IPA does not prove StikDebug or WoW execution will work.
set -euo pipefail

OUT="${1:-Wolkara-StikDebug-unsigned.ipa}"
case "$OUT" in
  /*) ;;
  *) OUT="$PWD/$OUT" ;;
esac
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export TOLKARA_SYSTEM_ROOTS=NO

mkdir -p logs build
LOG="logs/ipa-stikdebug-$(date +%Y%m%d-%H%M%S).log"
SYMROOT="$PWD/build/unsigned-stikdebug"

# Do not embed credentials, phone pairing data, or runner system roots.
TOLKARA_MODE=external-jit tools/generate.sh

if ! xcodebuild -project Tolkara.xcodeproj -target WolkaraExternalJIT \
    -configuration Release -sdk iphoneos -arch arm64 \
    SYMROOT="$SYMROOT" \
    NATIVE_GUEST_SHIMS=GENERIC TOLKARA_MODE=external-jit \
    TOLKARA_SYSTEM_ROOTS=NO \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    build > "$LOG" 2>&1; then
  grep -E "(error:|BUILD FAILED)" "$LOG" | tail -50 || true
  echo "Build failed. See $LOG" >&2
  exit 1
fi

APP="$SYMROOT/Release-iphoneos/WolkaraExternalJIT.app"
[ -d "$APP" ] || { echo "Expected app not found: $APP" >&2; exit 1; }

if find "$APP" -name CompatibilityRootCertificates.plist -print -quit | grep -q .; then
  echo "Refusing to package exported system roots" >&2
  exit 1
fi
if find "$APP" -name embedded.mobileprovision -print -quit | grep -q .; then
  echo "Refusing to package provisioning profiles" >&2
  exit 1
fi
if [ -d "$APP/PlugIns" ] && find "$APP/PlugIns" -name '*.appex' -print -quit | grep -q .; then
  echo "External JIT must not contain the integrated tunnel extension" >&2
  exit 1
fi

for library in "$APP"/Frameworks/*.dylib; do
  [ -f "$library" ] || continue
  codesign --force --sign - "$library" >> "$LOG" 2>&1
done
codesign --force --sign - --entitlements launcher/ExternalJIT.entitlements "$APP" >> "$LOG" 2>&1
codesign --verify --strict "$APP" >> "$LOG" 2>&1

ENTITLEMENTS="$(mktemp)"
trap 'rm -f "$ENTITLEMENTS"' EXIT
codesign -d --entitlements :- "$APP" > "$ENTITLEMENTS" 2>/dev/null
if ! /usr/libexec/PlistBuddy -c 'Print :get-task-allow' "$ENTITLEMENTS" | grep -qi '^true$'; then
  echo "The IPA must request get-task-allow for StikDebug; check signing" >&2
  exit 1
fi

STAGE="$PWD/build/stikdebug-ipa-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
rm -f "$OUT"
(cd "$STAGE" && zip -qry "$OUT" Payload)
rm -rf "$STAGE"
unzip -tq "$OUT" >/dev/null
echo "Created $OUT"
echo "This is an ad-hoc unsigned-for-distribution IPA. Re-sign using development"
echo "signing that preserves get-task-allow, then configure StikDebug and LocalDevVPN."
