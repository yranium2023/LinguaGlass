#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]]; then
  echo "LinguaGlass Apple Speech build requires macOS 26 or newer." >&2
  exit 1
fi
command -v xcodebuild >/dev/null || { echo "Install Xcode 26 first." >&2; exit 1; }
command -v swift >/dev/null || { echo "Swift 6.2 is required." >&2; exit 1; }
command -v rustc >/dev/null || { echo "Install Rust with rustup first." >&2; exit 1; }
command -v pnpm >/dev/null || { echo "Install pnpm first: corepack enable" >&2; exit 1; }

echo "Building Apple Speech bridge..."
swift build --package-path native/macos-speech-bridge -c release

TRIPLE="$(rustc -vV | awk '/host:/ {print $2}')"
mkdir -p src-tauri/binaries
cp native/macos-speech-bridge/.build/release/LinguaGlassSpeechBridge \
  "src-tauri/binaries/LinguaGlassSpeechBridge-${TRIPLE}"
chmod +x "src-tauri/binaries/LinguaGlassSpeechBridge-${TRIPLE}"

if [[ ! -d node_modules ]]; then
  pnpm install --frozen-lockfile
fi

echo "Building LinguaGlass DMG..."
pnpm tauri build --config src-tauri/tauri.macos.conf.json --no-sign
echo "DMG output: src-tauri/target/release/bundle/dmg/"
