$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
& (Join-Path $PSScriptRoot 'check.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Automated checks failed.' }
& .\.venv\Scripts\python.exe scripts\smoke_asr.py --realtime --device cuda
if ($LASTEXITCODE -ne 0) { throw 'Real English audio regression failed.' }
& (Join-Path $PSScriptRoot 'long-native-check.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Long native regression failed.' }
