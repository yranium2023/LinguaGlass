$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

# Use the repository-pinned toolchain when it is present. This keeps a release
# build independent from the developer's global Rust installation.
if (Test-Path -LiteralPath '.tools\cargo\bin\cargo.exe') {
    $env:RUSTUP_HOME = (Resolve-Path '.tools\rustup')
    $env:CARGO_HOME = (Resolve-Path '.tools\cargo')
    $env:PATH = "$(Resolve-Path '.tools\cargo\bin');$env:PATH"
}

if (!(Test-Path -LiteralPath 'node_modules\@tauri-apps\cli\tauri.js')) {
    throw 'Frontend dependencies are missing. Run npm install first.'
}

node node_modules\@tauri-apps\cli\tauri.js build
if ($LASTEXITCODE -ne 0) { throw 'Tauri release build failed.' }

$installer = Get-ChildItem 'src-tauri\target\release\bundle\msi\*.msi' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (!$installer) { throw 'MSI installer was not generated.' }
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $installer.FullName
Write-Host "Release installer: $($installer.FullName)"
Write-Host "SHA256: $($hash.Hash)"
