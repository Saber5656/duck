#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT_NAME="duck"
DUCK_VERSION="${DUCK_VERSION:-0.1.0}"
DUCK_BUILD_NUMBER="${DUCK_BUILD_NUMBER:-1}"
DUCK_SIGNING_IDENTITY="${DUCK_SIGNING_IDENTITY:--}"
DUCK_ARCHS="${DUCK_ARCHS:-}"
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
mkdir -p "$ROOT_DIR/.build/macos"

declare -a ARCH_BINARIES=()
build_arch() {
  local arch="$1"
  local triple="${arch}-apple-macosx13.0"
  local scratch_path="$ROOT_DIR/.build/macos/$arch"
  local bin_dir

  swift build \
    --disable-sandbox \
    --scratch-path "$scratch_path" \
    -c release \
    --product "$PRODUCT_NAME" \
    --triple "$triple"
  bin_dir="$(swift build \
    --disable-sandbox \
    --scratch-path "$scratch_path" \
    -c release \
    --show-bin-path \
    --triple "$triple")"
  [[ -x "$bin_dir/$PRODUCT_NAME" ]] || {
    echo "error: SwiftPM did not produce $arch/$PRODUCT_NAME" >&2
    exit 1
  }
  ARCH_BINARIES+=("$bin_dir/$PRODUCT_NAME")
}

plutil -lint "$INFO_PLIST" >/dev/null
plutil -lint "$ENTITLEMENTS" >/dev/null

if [[ -n "$DUCK_ARCHS" ]]; then
  IFS=',' read -r -a requested_archs <<< "$DUCK_ARCHS"
  for arch in "${requested_archs[@]}"; do
    case "$arch" in
      arm64|x86_64)
        build_arch "$arch"
        ;;
      *)
        echo "error: unsupported DUCK_ARCHS entry: $arch" >&2
        exit 1
        ;;
    esac
  done
  (( ${#ARCH_BINARIES[@]} > 0 )) || {
    echo "error: DUCK_ARCHS did not contain a supported architecture" >&2
    exit 1
  }
  EXECUTABLE="$ROOT_DIR/.build/macos/duck-universal"
  lipo -create "${ARCH_BINARIES[@]}" -output "$EXECUTABLE"
else
  swift build --disable-sandbox -c release --product "$PRODUCT_NAME"
  BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
  EXECUTABLE="$BIN_DIR/$PRODUCT_NAME"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$APP_SPRITES_DIR"

cp "$EXECUTABLE" "$MACOS_DIR/$PRODUCT_NAME"
cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
cp "$SPRITES_DIR"/* "$APP_SPRITES_DIR/"
chmod +x "$MACOS_DIR/$PRODUCT_NAME"

plutil -replace CFBundleShortVersionString -string "$DUCK_VERSION" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleVersion -string "$DUCK_BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

declare -a CODESIGN_ARGS=(
  --force
  --entitlements "$ENTITLEMENTS"
)
if [[ "$DUCK_SIGNING_IDENTITY" == "-" ]]; then
  CODESIGN_ARGS+=(--timestamp=none)
else
  CODESIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${CODESIGN_ARGS[@]}" --sign "$DUCK_SIGNING_IDENTITY" "$APP_DIR"

echo "Built $APP_DIR"
