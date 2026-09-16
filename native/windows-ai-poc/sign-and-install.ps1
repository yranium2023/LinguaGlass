param(
    [switch]$Install,
    [string]$PackagePath
)

$ErrorActionPreference = 'Stop'

$pocRoot = $PSScriptRoot
$repoRoot = Split-Path (Split-Path $pocRoot -Parent) -Parent
$artifactRoot = Join-Path $repoRoot 'artifacts\windows-ai-poc'
$packagePathMetadata = Join-Path $artifactRoot 'package-path.txt'
$artifactRootFull = [IO.Path]::GetFullPath($artifactRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar

if ([string]::IsNullOrWhiteSpace($PackagePath)) {
    if (!(Test-Path -LiteralPath $packagePathMetadata)) {
        throw 'No built package metadata was found. Run build.ps1 first or pass -PackagePath.'
    }
    $PackagePath = (Get-Content -LiteralPath $packagePathMetadata -Raw).Trim()
}

$packagePath = [IO.Path]::GetFullPath($PackagePath)
if (!$packagePath.StartsWith($artifactRootFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Package must be inside $artifactRootFull"
}
$certificatePath = Join-Path $artifactRoot 'LinguaGlass.WindowsAI.Poc.cer'
$subject = 'CN=LinguaGlass Development'
$friendlyName = 'LinguaGlass Windows AI PoC Development'
$sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'

if (!(Test-Path -LiteralPath $packagePath)) {
    throw "PoC package not found: $packagePath"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($packagePath)
try {
    $manifestEntry = $archive.GetEntry('AppxManifest.xml')
    if (!$manifestEntry) { throw 'The package does not contain AppxManifest.xml.' }
    $reader = [IO.StreamReader]::new($manifestEntry.Open())
    try { [xml]$packageManifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally {
    $archive.Dispose()
}

$packageName = [string]$packageManifest.Package.Identity.Name
$packageVersion = [Version]$packageManifest.Package.Identity.Version
$packagePublisher = [string]$packageManifest.Package.Identity.Publisher
if ($packagePublisher -ne $subject) {
    throw "Package publisher '$packagePublisher' does not match signing subject '$subject'."
}

if ($Install) {
    $installed = Get-AppxPackage -AllUsers -Name $packageName | Sort-Object Version -Descending | Select-Object -First 1
    if ($installed -and [Version]$installed.Version -ge $packageVersion) {
        throw "Installed package version $($installed.Version) is not older than $packageVersion. Rebuild with a higher -Version."
    }
}

$signTool = Get-ChildItem -LiteralPath $sdkRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64\SignTool.exe' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
if (!$signTool) {
    throw 'SignTool.exe was not found in the installed Windows SDK.'
}

$certificate = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $subject -and $_.FriendlyName -eq $friendlyName -and $_.NotAfter -gt (Get-Date).AddDays(30) } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if (!$certificate) {
    $certificate = New-SelfSignedCertificate `
        -Type Custom `
        -Subject $subject `
        -FriendlyName $friendlyName `
        -KeyAlgorithm RSA `
        -KeyLength 3072 `
        -HashAlgorithm SHA256 `
        -KeyUsage DigitalSignature `
        -KeyExportPolicy NonExportable `
        -CertStoreLocation Cert:\CurrentUser\My `
        -NotAfter (Get-Date).AddYears(2) `
        -TextExtension @('2.5.29.19={text}false', '2.5.29.37={text}1.3.6.1.5.5.7.3.3')
}

Export-Certificate -Cert $certificate -FilePath $certificatePath -Force | Out-Null
& $signTool sign /fd SHA256 /sha1 $certificate.Thumbprint /s My $packagePath
if ($LASTEXITCODE -ne 0) { throw 'PoC package signing failed.' }

if ($Install) {
    $trusted = Get-ChildItem Cert:\CurrentUser\Root |
        Where-Object Thumbprint -eq $certificate.Thumbprint |
        Select-Object -First 1
    if (!$trusted) {
        Import-Certificate -FilePath $certificatePath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
    }

    $machineTrusted = Get-ChildItem Cert:\LocalMachine\TrustedPeople |
        Where-Object Thumbprint -eq $certificate.Thumbprint |
        Select-Object -First 1
    if (!$machineTrusted) {
        Import-Certificate -FilePath $certificatePath -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
    }
}

& $signTool verify /pa /v $packagePath
$verificationExitCode = $LASTEXITCODE
if ($verificationExitCode -ne 0 -and !$Install) {
    throw 'PoC package signature verification failed.'
}
if ($verificationExitCode -ne 0 -and $Install) { throw 'PoC package signature verification failed after trusting the development certificate.' }

if ($Install) {
    Add-AppxPackage -Path $packagePath -ForceApplicationShutdown
    Write-Host "Installed LinguaGlass Windows AI Speech PoC $packageVersion."
}

Write-Host "Certificate: $certificatePath"
Write-Host "Signed package: $packagePath"
