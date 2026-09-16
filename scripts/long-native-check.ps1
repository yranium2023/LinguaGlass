$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$binaryPath = Join-Path $projectRoot 'src-tauri\target\debug\linguaglass.exe'
$embeddedFixture = Join-Path $projectRoot 'dist\test-audio.wav'
$fixture = Join-Path $projectRoot 'test-assets\jfk-rice-90s.wav'
$runtimeRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cache\codex-runtimes'
$playwright = Get-ChildItem $runtimeRoot -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'dependencies\node\node_modules\playwright' } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
if (-not $playwright) { throw 'Playwright is required for the native audio check.' }

Set-Location $projectRoot
node scripts\frontend.cjs build
if ($LASTEXITCODE -ne 0) { throw 'Frontend build failed.' }
Copy-Item -LiteralPath $fixture -Destination $embeddedFixture -Force
$env:TAURI_CONFIG = '{"app":{"windows":[{"label":"main","title":"LinguaGlass","width":1240,"height":840,"minWidth":860,"minHeight":640,"additionalBrowserArgs":"--remote-debugging-port=9223"},{"label":"overlay","title":"LinguaGlass Subtitles","url":"index.html?overlay=1","width":900,"height":330,"minWidth":480,"minHeight":280,"transparent":true,"decorations":false,"alwaysOnTop":true,"skipTaskbar":true,"visible":false,"resizable":true,"additionalBrowserArgs":"--remote-debugging-port=9223"}]}}'
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = $null
$env:PLAYWRIGHT_MODULE = $playwright

try {
    Get-CimInstance Win32_Process -Filter "Name='linguaglass.exe'" |
        Where-Object ExecutablePath -eq $binaryPath |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    . (Join-Path $PSScriptRoot 'native-env.ps1')
    cargo build --manifest-path src-tauri\Cargo.toml --features custom-protocol
    if ($LASTEXITCODE -ne 0) { throw 'Temporary native build failed.' }
    Start-Process -FilePath $binaryPath -WorkingDirectory $projectRoot -WindowStyle Hidden
    Start-Sleep -Seconds 4
    node scripts\native-audio-regression.cjs
    if ($LASTEXITCODE -ne 0) { throw 'Long native audio regression failed.' }
} finally {
    Get-CimInstance Win32_Process -Filter "Name='linguaglass.exe'" |
        Where-Object ExecutablePath -eq $binaryPath |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    $env:TAURI_CONFIG = $null
    $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = $null
    if (Test-Path -LiteralPath $embeddedFixture) {
        $resolvedFixture = (Resolve-Path -LiteralPath $embeddedFixture).Path
        if ($resolvedFixture -ne $embeddedFixture) { throw 'Unexpected embedded fixture path.' }
        Remove-Item -LiteralPath $resolvedFixture
    }
    node scripts\frontend.cjs build
    . (Join-Path $PSScriptRoot 'native-env.ps1')
    cargo build --manifest-path src-tauri\Cargo.toml --features custom-protocol
}
