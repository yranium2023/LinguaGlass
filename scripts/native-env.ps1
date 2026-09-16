$ErrorActionPreference = 'Stop'
$linguaRoot = Split-Path $PSScriptRoot -Parent
if (Test-Path -LiteralPath (Join-Path $linguaRoot '.tools\cargo\bin\cargo.exe')) {
    $env:RUSTUP_HOME = Join-Path $linguaRoot '.tools\rustup'
    $env:CARGO_HOME = Join-Path $linguaRoot '.tools\cargo'
    $env:PATH = (Join-Path $env:CARGO_HOME 'bin') + ';' + $env:PATH
}
if (!(Get-Command node -ErrorAction SilentlyContinue)) {
    $linguaNode = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin'
    if (Test-Path -LiteralPath (Join-Path $linguaNode 'node.exe')) { $env:PATH = $linguaNode + ';' + $env:PATH }
}
$linguaDevShell = Join-Path $linguaRoot '.tools\BuildTools\Common7\Tools\Launch-VsDevShell.ps1'
if (Test-Path -LiteralPath $linguaDevShell) {
    & $linguaDevShell -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
}
Set-Location $linguaRoot
