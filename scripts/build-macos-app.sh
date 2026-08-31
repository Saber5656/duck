#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT_NAME="duck"
APP_DIR="$ROOT_DIR/.build/macos/duck.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
INFO_PLIST="$ROOT_DIR/Resources/macOS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/macOS/duck.entitlements"
SPRITES_DIR="$ROOT_DIR/Resources/Sprites"
APP_SPRITES_DIR="$CONTENTS_DIR/Resources/Sprites"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: macOS is required to build the duck app bundle" >&2
  exit 1
fi

cd "$ROOT_DIR"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/module-cache}"
export SWIFTPM_HOME="${SWIFTPM_HOME:-$ROOT_DIR/.build/swiftpm-home}"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_HOME"

plutil -lint "$INFO_PLIST" >/dev/null
plutil -lint "$ENTITLEMENTS" >/dev/null

swift build --disable-sandbox -c release --product "$PRODUCT_NAME"
BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
EXECUTABLE="$BIN_DIR/$PRODUCT_NAME"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$APP_SPRITES_DIR"

cp "$EXECUTABLE" "$MACOS_DIR/$PRODUCT_NAME"
cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
cp "$SPRITES_DIR"/* "$APP_SPRITES_DIR/"
chmod +x "$MACOS_DIR/$PRODUCT_NAME"

codesign --force \
  --sign - \
  --entitlements "$ENTITLEMENTS" \
  --timestamp=none \
  "$APP_DIR"

echo "Built $APP_DIR"
