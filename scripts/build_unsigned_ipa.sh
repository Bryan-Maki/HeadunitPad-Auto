#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/.build/UnsignedIPA}"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
APP_NAME="HeadunitPad"

for tool in xcodebuild zip unzip; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required tool not found: $tool" >&2
    exit 1
  fi
done

echo "==> Building unsigned Release app"
xcodebuild clean build \
  -workspace "$ROOT_DIR/HeadunitPad.xcworkspace" \
  -scheme HeadunitPad \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES

APP="$DERIVED_DATA/Build/Products/Release-iphoneos/$APP_NAME.app"
BINARY="$APP/$APP_NAME"
if [[ ! -f "$BINARY" ]]; then
  echo "error: expected app executable not found: $BINARY" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/headunitpad-ipa.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Packaging standard unsigned IPA"
mkdir -p "$OUTPUT_DIR" "$WORK_DIR/Payload"
cp -R "$APP" "$WORK_DIR/Payload/$APP_NAME.app"
IPA="$OUTPUT_DIR/$APP_NAME.ipa"
rm -f "$IPA"
(
  cd "$WORK_DIR"
  zip -qry "$IPA" Payload
)

echo "==> Verifying packaged executable"
mkdir "$WORK_DIR/verification"
unzip -q "$IPA" -d "$WORK_DIR/verification"
PACKAGED_APP="$WORK_DIR/verification/Payload/$APP_NAME.app"
PACKAGED_BINARY="$PACKAGED_APP/$APP_NAME"

test -f "$PACKAGED_APP/Info.plist"
test -d "$PACKAGED_APP/Frameworks"
test -f "$PACKAGED_BINARY"

# Verify no private USB entitlements are present
if command -v codesign >/dev/null 2>&1; then
  if codesign -d --entitlements :- "$PACKAGED_BINARY" 2>/dev/null | grep -E "AppleUSBHost|com.apple.vm.device-access" >/dev/null 2>&1; then
    echo "error: packaged binary contains private USB entitlements" >&2
    exit 1
  fi
fi

echo "==> Successfully created standard unsigned IPA:"
echo "==> $IPA"
