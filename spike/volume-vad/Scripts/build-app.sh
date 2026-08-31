#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

swift build -c debug

bin_dir="$(swift build -c debug --show-bin-path)"
app_dir="$PWD/.build/DuckVADSpike.app"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"

cp "$bin_dir/DuckVADSpike" "$app_dir/Contents/MacOS/DuckVADSpike"
cp "App/Info.plist" "$app_dir/Contents/Info.plist"

codesign --force --sign - --entitlements "App/DuckVADSpike.entitlements" "$app_dir"

echo "$app_dir"
