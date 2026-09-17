#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="$PROJECT_ROOT/native/macos-app"
OUTPUT_ROOT="$PROJECT_ROOT/dist"
APP_BUNDLE="$OUTPUT_ROOT/LinguaGlass.app"
ICON_MASTER="$APP_ROOT/Resources/AppIconMono-1024.png"
ICON_SET="$APP_ROOT/Resources/AppIconMono.iconset"

cd "$PROJECT_ROOT"
swift build --package-path "$APP_ROOT" -c release
# The legacy Tauri macOS config still references the retired speech bridge.
# This standalone native bundle only needs the Rust translation service.
TAURI_CONFIG='{"bundle":{"externalBin":[]}}' \
    cargo build --manifest-path "$PROJECT_ROOT/src-tauri/Cargo.toml" --release --bin linguaglass-service

xcrun swift "$PROJECT_ROOT/scripts/generate-native-icon.swift" "$ICON_MASTER"
rm -rf "$ICON_SET"
mkdir -p "$ICON_SET"
for spec in "16:icon_16x16.png" "32:icon_16x16@2x.png" "32:icon_32x32.png" \
            "64:icon_32x32@2x.png" "128:icon_128x128.png" "256:icon_128x128@2x.png" \
            "256:icon_256x256.png" "512:icon_256x256@2x.png" "512:icon_512x512.png" \
            "1024:icon_512x512@2x.png"; do
    pixels="${spec%%:*}"
    filename="${spec#*:}"
    sips -z "$pixels" "$pixels" "$ICON_MASTER" --out "$ICON_SET/$filename" >/dev/null
done
iconutil -c icns "$ICON_SET" -o "$APP_ROOT/Resources/AppIconMono.icns"
rm -rf "$ICON_SET"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$APP_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$APP_ROOT/Resources/AppIconMono.icns" "$APP_BUNDLE/Contents/Resources/AppIconMono.icns"
cp "$APP_ROOT/.build/release/LinguaGlassMac" "$APP_BUNDLE/Contents/MacOS/LinguaGlassMac"
cp "$PROJECT_ROOT/src-tauri/target/release/linguaglass-service" "$APP_BUNDLE/Contents/MacOS/linguaglass-service"
chmod +x "$APP_BUNDLE/Contents/MacOS/LinguaGlassMac" \
    "$APP_BUNDLE/Contents/MacOS/linguaglass-service"
xattr -cr "$APP_BUNDLE"
codesign --force --sign - \
    --identifier com.linguaglass.native.translation \
    --requirements '=designated => identifier "com.linguaglass.native.translation"' \
    "$APP_BUNDLE/Contents/MacOS/linguaglass-service"
codesign --force --sign - \
    --identifier com.linguaglass.native \
    --requirements '=designated => identifier "com.linguaglass.native"' \
    "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE"
xattr -d com.apple.FinderInfo "$APP_BUNDLE" 2>/dev/null || true
xattr -d com.apple.ResourceFork "$APP_BUNDLE" 2>/dev/null || true
codesign --verify --deep --strict "$APP_BUNDLE"

echo "$APP_BUNDLE"
