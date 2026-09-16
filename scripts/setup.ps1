param([switch]$DownloadModel, [string]$Model = 'distil-large-v3')
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (!(Test-Path -LiteralPath '.venv\Scripts\python.exe')) {
    python -m venv .venv
    if ($LASTEXITCODE -ne 0) { throw 'Python virtual environment creation failed.' }
}
& .\.venv\Scripts\python.exe -m pip install -r asr-sidecar\requirements.lock.txt
if ($LASTEXITCODE -ne 0) { throw 'ASR dependency installation failed.' }
& .\.venv\Scripts\python.exe asr-sidecar\main.py --doctor
if ($LASTEXITCODE -ne 0) { throw 'ASR environment check failed.' }
if ($DownloadModel) {
    & .\.venv\Scripts\python.exe asr-sidecar\main.py --download-model --model $Model
    if ($LASTEXITCODE -ne 0) { throw 'Model download failed.' }
}
Write-Host 'Python environment is ready. Run npm install, then npm run desktop with Rust/MSVC available.'
