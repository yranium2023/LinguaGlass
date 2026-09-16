# LinguaGlass Windows AI Speech PoC

This isolated packaged WinForms application validates the Windows AI Speech model lifecycle and
microphone streaming before any Windows AI code is connected to the Tauri application.

## Safety boundary

- It does not replace or modify the Distil backend.
- It asks for confirmation before `EnsureReadyAsync()` can download a system model.
- It must run with MSIX package identity and the `systemAIModels` capability.
- WASAPI push-stream support is added only after the packaged microphone path is verified.

The PoC pins `Microsoft.WindowsAppSDK` `2.4.1-Experimental`. The stable `2.4.0` package was
compile-checked first and does not contain `Microsoft.Windows.AI.Speech`. This dependency must not
enter the production application until the P0 Go/No-Go review explicitly accepts the API risk or
Microsoft promotes Speech to a stable channel.

## Build

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File native\windows-ai-poc\build.ps1 -Version 0.1.0.2
```

The first restore requires network access. The build publishes a self-contained x64 executable and
uses the Windows SDK `MakeAppx.exe`, so Visual Studio or a WAP project is not required. The package
is deliberately unsigned during the first compile-only stage; a development certificate and install
script are added after the API surface is confirmed.

All .NET, NuGet, HTTP, and temporary build state created by this script is stored under the ignored
repository directory `.tools\windows-ai-poc` on the same drive as the checkout. This prevents PoC
builds from silently filling the system drive.

To create/reuse the scoped code-signing development certificate, trust it for the current user, sign the package,
and install the PoC:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File native\windows-ai-poc\sign-and-install.ps1 -Install
```

Every changed package must use a higher four-part version than the installed package. The build
writes the exact package path to ignored artifact metadata, which the signing script consumes; the
installer rejects equal-version content changes and accidental downgrades before deployment.

The PoC writes only backend lifecycle and error records to
`%LOCALAPPDATA%\LinguaGlass\WindowsAIPoc\status.log`. Partial/final transcript text is intentionally
kept in memory and is never written to this diagnostic file.

The certificate is added to the current user's trusted root store and the machine's Trusted People
store for local PoC testing. It has only the code-signing EKU, is not exportable, is not a production
signing identity, and must never be used for a public GitHub Release.
