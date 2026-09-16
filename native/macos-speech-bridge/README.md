# LinguaGlass macOS Speech Bridge

Native macOS 26 bridge for Apple `SpeechAnalyzer` / `SpeechTranscriber`.
It captures the default microphone with AVAudioEngine or system audio with
ScreenCaptureKit and writes JSON Lines events to stdout.

```bash
swift build -c release
.build/release/LinguaGlassSpeechBridge --doctor --locale en-US
.build/release/LinguaGlassSpeechBridge --prepare --locale en-US
.build/release/LinguaGlassSpeechBridge --mode microphone --locale en-US
```

Press Return to stop an active recognition session. System audio requires the
Screen & System Audio Recording permission; microphone mode requires microphone
permission.
