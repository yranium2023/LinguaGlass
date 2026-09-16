$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'native-env.ps1')
if (!(Get-Command node -ErrorAction SilentlyContinue)) { throw 'Install Node.js 22+ first.' }
if (!(Get-Command cargo -ErrorAction SilentlyContinue)) { throw 'Install Rust MSVC and C++ Build Tools first.' }
if (!(Test-Path -LiteralPath 'node_modules\@tauri-apps\cli\tauri.js')) { throw 'Run npm install first.' }
node node_modules\@tauri-apps\cli\tauri.js dev
if ($LASTEXITCODE -ne 0) { throw 'Desktop startup failed. See the message above.' }
