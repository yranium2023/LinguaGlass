# Changelog

## 0.1.0 - Windows Release candidate

- Distil-Whisper is the supported Windows ASR backend.
- Distil models are downloaded on demand into the user's application data
  directory; the installer does not include model weights.
- The packaged application includes its Python ASR runtime and does not depend
  on a developer checkout or a visible console window.
- Added a reproducible MSI release build script and SHA-256 output.
- Windows AI Speech remains documented as a rejected experimental PoC and is not
  part of this release.
