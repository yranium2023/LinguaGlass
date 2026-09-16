$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'native-env.ps1')
& .\.venv\Scripts\python.exe -m unittest discover -s asr-sidecar\tests -v
if ($LASTEXITCODE -ne 0) { throw 'Python tests failed.' }
node node_modules\vitest\vitest.mjs run
if ($LASTEXITCODE -ne 0) { throw 'Frontend tests failed.' }
node scripts\frontend.cjs build
if ($LASTEXITCODE -ne 0) { throw 'Frontend build failed.' }
cargo test --manifest-path src-tauri\Cargo.toml
if ($LASTEXITCODE -ne 0) { throw 'Rust tests failed.' }
