param(
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')]
    [string]$Version = '0.1.0.2'
)

$ErrorActionPreference = 'Stop'

$pocRoot = $PSScriptRoot
$repoRoot = Split-Path (Split-Path $pocRoot -Parent) -Parent
$dotnetRoot = Join-Path $repoRoot '.tools\dotnet'
$dotnet = Join-Path $dotnetRoot 'dotnet.exe'
$sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
$toolStateRoot = Join-Path $repoRoot '.tools\windows-ai-poc'
$nugetPackages = Join-Path $toolStateRoot 'nuget-packages'
$nugetHttpCache = Join-Path $toolStateRoot 'nuget-http-cache'
$dotnetCliHome = Join-Path $toolStateRoot 'dotnet-cli-home'
$buildTemp = Join-Path $toolStateRoot "temp-$PID"

if (!(Test-Path -LiteralPath $dotnet)) {
    throw 'Missing local .NET SDK. Install it into .tools\dotnet before building the PoC.'
}
$env:DOTNET_ROOT = $dotnetRoot
$env:PATH = $dotnetRoot + ';' + $env:PATH
$env:NUGET_PACKAGES = $nugetPackages
$env:NUGET_HTTP_CACHE_PATH = $nugetHttpCache
$env:DOTNET_CLI_HOME = $dotnetCliHome
$env:TEMP = $buildTemp
$env:TMP = $buildTemp

@($nugetPackages, $nugetHttpCache, $dotnetCliHome, $buildTemp) | ForEach-Object {
    New-Item -ItemType Directory -Path $_ -Force | Out-Null
}

$appProject = Join-Path $pocRoot 'LinguaGlass.WindowsAI.Poc\LinguaGlass.WindowsAI.Poc.csproj'
$packageSource = Join-Path $pocRoot 'LinguaGlass.WindowsAI.Poc.Package'
$artifactRoot = Join-Path $repoRoot 'artifacts\windows-ai-poc'
$publishDir = Join-Path $artifactRoot 'publish'
$stageDir = Join-Path $artifactRoot 'stage'
$packagePath = Join-Path $artifactRoot "LinguaGlass.WindowsAI.Poc_${Version}_x64.msix"
$packagePathMetadata = Join-Path $artifactRoot 'package-path.txt'

function Assert-ChildPath([string]$Parent, [string]$Child) {
    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $childFull = [IO.Path]::GetFullPath($Child)
    if (!$childFull.StartsWith($parentFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify path outside $parentFull"
    }
}

Assert-ChildPath $repoRoot $artifactRoot
Assert-ChildPath $artifactRoot $stageDir

$makeAppx = Get-ChildItem -LiteralPath $sdkRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64\MakeAppx.exe' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
if (!$makeAppx) {
    throw 'MakeAppx.exe was not found in the installed Windows SDK.'
}

& $dotnet restore $appProject
if ($LASTEXITCODE -ne 0) { throw 'Windows AI PoC restore failed.' }

& $dotnet publish $appProject -c Debug -r win-x64 --self-contained true -o $publishDir --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Windows AI PoC publish failed.' }

if (Test-Path -LiteralPath $stageDir) {
    Remove-Item -LiteralPath $stageDir -Recurse -Force
}
New-Item -ItemType Directory -Path $stageDir | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stageDir 'Images') | Out-Null
Copy-Item -Path (Join-Path $publishDir '*') -Destination $stageDir -Recurse -Force
$stagedManifest = Join-Path $stageDir 'AppxManifest.xml'
Copy-Item -LiteralPath (Join-Path $packageSource 'Package.appxmanifest') -Destination $stagedManifest
[xml]$manifest = Get-Content -LiteralPath $stagedManifest -Raw
$manifest.Package.Identity.Version = $Version
$manifest.Save($stagedManifest)
Copy-Item -LiteralPath (Join-Path $repoRoot 'src-tauri\icons\Square150x150Logo.png') -Destination (Join-Path $stageDir 'Images\Square150x150Logo.png')
Copy-Item -LiteralPath (Join-Path $repoRoot 'src-tauri\icons\Square44x44Logo.png') -Destination (Join-Path $stageDir 'Images\Square44x44Logo.png')
Copy-Item -LiteralPath (Join-Path $repoRoot 'src-tauri\icons\StoreLogo.png') -Destination (Join-Path $stageDir 'Images\StoreLogo.png')

& $makeAppx pack /d $stageDir /p $packagePath /o
if ($LASTEXITCODE -ne 0) { throw 'Windows AI PoC MSIX creation failed.' }

Set-Content -LiteralPath $packagePathMetadata -Value $packagePath -Encoding UTF8

Write-Host "Unsigned PoC package: $packagePath"
