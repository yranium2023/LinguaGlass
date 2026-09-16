# LinguaGlass architecture · Prototype 0.1

## Boundaries

React/TypeScript renders controls, transcript and a separate transparent Tauri overlay.
Rust owns microphone/system audio capture, process lifecycle, the credential store, the translation
queue and session journals. A persistent Python process owns resampling, Silero VAD
and faster-whisper. Only finalized English text, a bounded context and a glossary
can reach the fixed HTTPS DeepSeek endpoint. Audio is never included in HTTP requests.

## Data flow

1. CPAL captures microphone or Windows playback PCM on its native callback thread.
   Opening an output endpoint as an input stream uses CPAL's WASAPI loopback path.
2. A bounded channel transfers mono float samples to the sidecar writer. Capture
   never waits for Python. Overflow produces an explicit discontinuity warning.
3. JSON Lines over anonymous stdin/stdout pipes carry base64 little-endian float32
   audio, its native sample rate and capture timestamp. No listening port.
4. Python uses a stateful SOXR resampler to produce 16 kHz mono. A rolling Silero
   detector closes utterances after 640 ms silence, or 12 seconds maximum.
5. One model worker loads distil-large-v3 once per session. It prioritizes a bounded
   final queue over a replaceable partial snapshot. Partial results never translate.
6. Rust records final text immediately. A separate bounded Tokio worker requests
   streaming Chinese translations with the last 3 finalized English segments.
7. Stable session/segment IDs correlate asynchronous events. React keeps only 300
   recent rows; append-only local JSONL journals retain the complete session.

## Backpressure and termination

Capture channel: 64 callbacks; ASR final queue: 8 utterances; partial: 1 replaceable
snapshot; translation queue: 64 sentences. Full queues are reported explicitly;
they never silently grow. Missing key, HTTP failure or saturation never stops English
recognition. Stopping closes capture, flushes the sidecar, then drains translation
within a bounded timeout. Closing the main window kills the child process.

## Security

API keys are saved only through Rust keyring into the OS credential manager.
The UI clears the password field after saving. No key in settings, logs, environment
files, URLs or Python IPC. Provider error bodies are never forwarded into logs/UI.
The webview CSP forbids direct remote connections; Rust fixes the provider URL and
disables redirects. The overlay has no permission to run privileged app commands.
Session transcripts are sensitive local text, saved in the OS app data directory.

## Scope and deliberate limits

This prototype implements microphone input and Windows WASAPI loopback; it
does not claim a completed cross-platform MVP. Simultaneous inputs,
ScreenCaptureKit/PipeWire backends, packaged Python distribution, two-hour soak tests
and measured end-to-end latency remain later milestones. The UI marks unavailable
input modes and uncached models. CUDA is supported when installed; CPU int8 is the default. CTranslate2
does not expose a Metal backend, so Metal is not offered as a working setting.
The model is re-used within a session; cross-session reuse is a future optimization.

## References checked 2026-09-15

- https://v2.tauri.app/develop/calling-rust/
- https://github.com/SYSTRAN/faster-whisper
- https://docs.rs/cpal/0.16.0/cpal/
- https://api-docs.deepseek.com/api/create-chat-completion/
- https://api-docs.deepseek.com/guides/thinking_mode/
- https://docs.rs/crate/keyring/3.6.2
