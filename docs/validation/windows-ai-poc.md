# Windows AI Speech PoC Validation

## Status

P0.1 packaged application build, signing, installation, upgrade, and visible launch are complete.
The installed app completed user-approved model preparation and now reports `Ready`. Microphone
partial/final recognition and repeated start/stop remain to be validated.

## Environment

- Date: 2026-09-16
- Windows build: `26200.7623`
- Windows SDK: `10.0.26100.0`
- Local .NET SDK: `8.0.425` in `.tools/dotnet` (ignored by Git)
- Windows App SDK tested stable package: `2.4.0`
- Windows App SDK PoC package: `2.4.1-Experimental`
- Target: `net8.0-windows10.0.26100.0`, x64, self-contained
- CPU: Intel Core Ultra 7 270K Plus, 24 physical cores, 3.7 GHz reported maximum, 36 MB L3
- Installed speech component: `Microsoft.Windows.AI.Speech.Preview.NPU 1.2607.112.0` (about 915 MB)

## Findings

1. `Microsoft.WindowsAppSDK 2.4.0` does not expose `Microsoft.Windows.AI.Speech`; compiling the
   Speech PoC against the current stable package fails at the namespace boundary.
2. `2.4.1-Experimental` exposes `SpeechRecognitionModel`, `AudioConfiguration`, and
   `StreamingRecognition`. The PoC compiles successfully and the compiler marks these APIs as
   evaluation-only.
3. The repository's existing Visual Studio Build Tools installation did not contain Desktop Bridge,
   and the standalone Build Tools product does not expose the Visual Studio MSIX component ID used
   by full IDE editions.
4. A reproducible no-IDE packaging path works: self-contained `dotnet publish`, explicit
   `AppxManifest.xml`, then Windows SDK `MakeAppx.exe`.
5. The resulting MSIX signs successfully with the scoped development certificate and installs after
   the public certificate is trusted in the machine Trusted People store.
6. Calling `GetReadyState()` synchronously before the first form was shown blocked the UI on this
   machine. PoC `0.1.0.1` now displays the window first and performs the check off the UI thread with
   a 15-second timeout.
7. PoC build state is redirected to the repository-local ignored `.tools/windows-ai-poc` directory
   so future restores do not silently consume the system drive.
8. Installed PoC `0.1.0.2` returned `ready-state=NotReady` in about 1.2 seconds. The system does not
   classify the API as unsupported or user-disabled; the system speech model still needs explicit
   user-approved preparation.
9. Model preparation triggered a Windows Update download and installed the NPU speech component.
   `EnsureReadyAsync()` returned `Failure`, but the immediate authoritative `GetReadyState()` check
   returned `Ready`. The production backend must always re-check final readiness and must not treat
   the asynchronous result alone as the final state.
10. Microsoft documents that non-preinstalled speech models are delivered on demand through Windows
    Update and that preparation reports `Installing`, `Caching`, `Loading`, and completion progress.
    The next PoC build subscribes to `SpeechRecognitionModelProgress`; this change compiles cleanly.

## Package identity and capabilities

- Package identity: `LinguaGlass.WindowsAI.Poc`
- Publisher: `CN=LinguaGlass Development`
- Minimum Windows: `10.0.26100.0`
- MaxVersionTested: `10.0.26226.0`
- Capabilities: `runFullTrust`, `systemAIModels`, `microphone`

The development certificate is local-test-only, code-signing-only, non-exportable, and is not a
candidate for the public release signing identity.

## Reproduction

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File native\windows-ai-poc\build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File native\windows-ai-poc\sign-and-install.ps1 -Install
```

## Interactive P0.1 checklist

- [x] App starts from its installed package identity (`0.1.0.2`) and shows a responsive window.
- [x] Initial Windows AI Speech ready state is visible (`NotReady`).
- [x] Model preparation asks for user consent before `EnsureReadyAsync()`.
- [x] System model preparation installs the component and final readiness becomes `Ready`; the
      inconsistent asynchronous `Failure` result is recorded as an experimental API issue.
- [ ] Default microphone starts and emits partial transcript.
- [ ] Spoken phrase produces final transcript.
- [ ] Stop and restart work three consecutive times.

## Gate after P0.1

Do not start production backend integration yet. After the checklist passes, implement
`SpeechAudioProvider` and the explicit 16 kHz, signed 16-bit, mono PCM contract for the existing Rust
WASAPI Loopback pipeline.

## Primary references

- [Speech Recognition with Windows AI APIs](https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition)
- [SpeechRecognitionModel.EnsureReadyAsync](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodel.ensurereadyasync)
- [SpeechRecognitionModelProgress](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodelprogress)
