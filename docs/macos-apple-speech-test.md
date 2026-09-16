# macOS 26 Apple Speech test

Target: Apple Silicon, macOS 26, Xcode 26. This first build validates local
English transcription only. It does not send Apple Speech text to DeepSeek.

## Build

```bash
git clone https://github.com/yranium2023/LinguaGlass.git
cd LinguaGlass
xcode-select --install
corepack enable
pnpm install --frozen-lockfile
curl https://sh.rustup.rs -sSf | sh
source "$HOME/.cargo/env"
chmod +x scripts/build-macos.sh
./scripts/build-macos.sh
```

The output is under `src-tauri/target/release/bundle/dmg/`. If Gatekeeper blocks
the locally built unsigned app, Control-click it in Finder and choose Open.

## Test order

1. Launch the app and open Settings.
2. Confirm the backend reads `Apple Speech` and click Prepare Model if needed.
3. Select Microphone, start listening, grant microphone access, and speak English.
4. Stop and start again to verify lifecycle recovery.
5. Select System Audio, start listening, grant Screen & System Audio Recording,
   restart the app if macOS requests it, and play an English video.
6. Verify partial text is replaced by final text without duplicates.
7. Keep system audio recognition running for 30 minutes.

## Report back

Please send the output of these commands and a screenshot of any user-visible
error. Do not send API keys or private transcript content.

```bash
sw_vers
xcodebuild -version
uname -m
native/macos-speech-bridge/.build/release/LinguaGlassSpeechBridge --doctor --locale en-US
```

Also report whether microphone and system audio each produced partial and final
English text, and the approximate model preparation time.
