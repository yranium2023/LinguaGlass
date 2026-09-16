#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]]; then
  echo "LinguaGlass Apple Speech build requires macOS 26 or newer." >&2
  exit 1
fi
command -v xcodebuild >/dev/null || { echo "Install Xcode 26 first." >&2; exit 1; }
command -v xcrun >/dev/null || { echo "Xcode command-line tools are unavailable." >&2; exit 1; }
command -v rustc >/dev/null || { echo "Install Rust with rustup first." >&2; exit 1; }
command -v pnpm >/dev/null || { echo "Install pnpm first: corepack enable" >&2; exit 1; }

SWIFT_VERSION="$(xcrun swift --version | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -1)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "${SWIFT_VERSION}" != 6.2* && "${SWIFT_VERSION}" != 6.3* && "${SWIFT_VERSION}" != 6.4* ]]; then
  echo "Apple Speech requires Xcode 26+ with Swift 6.2+. Active Swift is ${SWIFT_VERSION:-unknown}." >&2
  echo "Install Xcode 26, then run:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi
if [[ "${SDK_VERSION%%.*}" -lt 26 ]]; then
  echo "Apple Speech requires the macOS 26 SDK. Active SDK is ${SDK_VERSION}." >&2
  echo "Switch to Xcode 26 with xcode-select before rebuilding." >&2
  exit 1
fi

echo "Using $(xcodebuild -version | tr '\n' ' '), Swift ${SWIFT_VERSION}, macOS SDK ${SDK_VERSION}"

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
