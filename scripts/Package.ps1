#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$Repository = 'pearl-eye/Mortal-MJ-CN',
    [string]$ReleaseTag = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$pluginName = 'MortalMJPlugin'
$repoRoot = Split-Path -Parent $PSScriptRoot
$artifacts = Join-Path $repoRoot 'artifacts'
$packageDirectory = Join-Path $artifacts $pluginName
$files = @('MortalMJPlugin.dll', 'MortalMJPlugin.json', 'MortalMJPlugin.deps.json', 'icon.png')
$utf8 = [System.Text.UTF8Encoding]::new($false)

$upstreamPath = Join-Path $repoRoot 'upstream-version.json'
if (-not [System.IO.File]::Exists($upstreamPath)) {
    throw 'The upstream version evidence file is required.'
}
$upstream = Get-Content -LiteralPath $upstreamPath -Raw | ConvertFrom-Json -AsHashtable
if ($upstream['InternalName'] -cne $pluginName -or $upstream['DalamudApiLevel'] -ne 15) {
    throw 'Upstream version evidence must identify MortalMJPlugin for Dalamud API 15.'
}
$upstreamVersion = [string]$upstream['AssemblyVersion']
if ($upstreamVersion -notmatch '^\d+\.\d+\.\d+\.\d+$' -or
    [string]$upstream['UpstreamCommit'] -notmatch '^[0-9a-f]{40}$' -or
    [string]$upstream['UpstreamManifestBlobSha'] -notmatch '^[0-9a-f]{40}$' -or
    [string]$upstream['OriginalAssemblySha256'] -notmatch '^[0-9a-f]{64}$') {
    throw 'Upstream version evidence is incomplete or invalid.'
}

foreach ($name in $files) {
    $path = Join-Path $repoRoot $name
    if (-not [System.IO.File]::Exists($path)) {
        throw "Required release file is missing: $name"
    }
    if ((Get-Item -LiteralPath $path).Length -eq 0) {
        throw "Required release file is empty: $name"
    }
}

$manifestPath = Join-Path $repoRoot "$pluginName.json"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
if ($manifest -isnot [System.Collections.IDictionary]) {
    throw 'The plugin manifest must be a JSON object.'
}
if ($manifest['InternalName'] -cne $pluginName) {
    throw "Manifest InternalName must be $pluginName."
}
if ([string]::IsNullOrWhiteSpace([string]$manifest['Name'])) {
    throw 'Manifest Name must not be empty.'
}
if ($manifest['DalamudApiLevel'] -ne 15) {
    throw 'This release must target Dalamud API 15.'
}

# These fields belong to an installed copy, never to a distributable manifest.
$localFields = @('WorkingPluginId', 'InstalledFromUrl', 'Disabled', 'Testing', 'ScheduledForDeletion', 'IsThirdParty')
foreach ($field in $localFields) {
    if ($manifest.Contains($field)) {
        throw "Remove local installation state from the manifest: $field"
    }
}

# GetAssemblyName reads PE metadata only. It does not load the plugin, resolve
# Dalamud, instantiate Plugin, or start the external Mortal process.
$assemblyPath = Join-Path $repoRoot "$pluginName.dll"
$assembly = [System.Reflection.AssemblyName]::GetAssemblyName($assemblyPath)
if ($assembly.Name -cne $pluginName) {
    throw "Unexpected assembly name: $($assembly.Name)"
}
$version = $assembly.Version.ToString()
if ($version -cne $upstreamVersion) {
    throw "The DLL version must equal the verified upstream version: $upstreamVersion. Do not increment a repair release."
}
if ([string]$manifest['AssemblyVersion'] -cne $version) {
    throw "Manifest AssemblyVersion must match the DLL: $version"
}
$fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($assemblyPath)
if ($fileVersion.FileVersion -cne $upstreamVersion -or $fileVersion.ProductVersion -cne $upstreamVersion) {
    throw "FileVersion and InformationalVersion must also equal the upstream version: $upstreamVersion"
}

$assemblyStream = [System.IO.File]::OpenRead($assemblyPath)
$pe = [System.Reflection.PortableExecutable.PEReader]::new($assemblyStream)
try {
    if ($pe.PEHeaders.CoffHeader.Machine -ne [System.Reflection.PortableExecutable.Machine]::Amd64) {
        throw 'The plugin DLL must target x64.'
    }
} finally {
    $pe.Dispose()
    $assemblyStream.Dispose()
}

$expectedTag = "cn-v$version"
if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
    $ReleaseTag = $expectedTag
}
if ($ReleaseTag -cne $expectedTag) {
    throw "Release tag must match the packaged version: $expectedTag"
}

# The framework references are supplied by Dalamud. This binary-only package
# has no other managed runtime assets to ship.
$depsPath = Join-Path $repoRoot "$pluginName.deps.json"
$deps = Get-Content -LiteralPath $depsPath -Raw | ConvertFrom-Json -AsHashtable
$libraryKey = "$pluginName/$version"
if ($deps['libraries'].Count -ne 1 -or -not $deps['libraries'].Contains($libraryKey)) {
    throw "The dependency manifest must contain only $libraryKey."
}
$runtimeTarget = [string]$deps['runtimeTarget']['name']
if ($runtimeTarget -notmatch '^\.NETCoreApp,Version=v10\.0(?:/[^/]+)?$') {
    throw 'The dependency manifest must target .NET 10.'
}
$target = $deps['targets'][$runtimeTarget]
if ($null -eq $target -or $target.Count -ne 1 -or -not $target.Contains($libraryKey)) {
    throw 'Unexpected dependency target entries.'
}
$runtimeAssets = $target[$libraryKey]['runtime']
if ($null -eq $runtimeAssets -or $runtimeAssets.Count -ne 1 -or -not $runtimeAssets.Contains("$pluginName.dll")) {
    throw 'The dependency manifest must reference only the plugin DLL.'
}

[System.IO.Directory]::CreateDirectory($packageDirectory) | Out-Null
# Do not silently collect or delete unrelated files from an old staging folder.
foreach ($entry in Get-ChildItem -LiteralPath $packageDirectory -Force) {
    if ($entry.PSIsContainer -or $entry.Name -cnotin $files) {
        throw "Unexpected file in the package staging directory: $($entry.Name)"
    }
}
foreach ($name in $files) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $name) -Destination (Join-Path $packageDirectory $name) -Force
}

$zipPath = Join-Path $artifacts 'latest.zip'
$zipStream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::Create)
$archive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in ($files | Sort-Object -CaseSensitive)) {
        $entry = $archive.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $inputStream = [System.IO.File]::OpenRead((Join-Path $packageDirectory $name))
        $outputStream = $entry.Open()
        try {
            $inputStream.CopyTo($outputStream)
        } finally {
            $outputStream.Dispose()
            $inputStream.Dispose()
        }
    }
} finally {
    $archive.Dispose()
    $zipStream.Dispose()
}

$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    if ($archive.Entries.Count -ne $files.Count) {
        throw 'The ZIP does not contain exactly four release files.'
    }
    foreach ($entry in $archive.Entries) {
        if ($entry.FullName -cnotin $files) {
            throw "Unexpected ZIP entry: $($entry.FullName)"
        }
        $stream = $entry.Open()
        try {
            $actualHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($stream))
        } finally {
            $stream.Dispose()
        }
        $expectedHash = (Get-FileHash -LiteralPath (Join-Path $repoRoot $entry.FullName) -Algorithm SHA256).Hash
        if ($actualHash -cne $expectedHash) {
            throw "ZIP entry differs from the release input: $($entry.FullName)"
        }
    }
} finally {
    $archive.Dispose()
}

$downloadUrl = "https://github.com/$Repository/releases/download/$ReleaseTag/latest.zip"
$repoEntry = [ordered]@{}
foreach ($key in $manifest.Keys) {
    $repoEntry[$key] = $manifest[$key]
}
$repoEntry['RepoUrl'] = "https://github.com/$Repository"
$repoEntry['IconUrl'] = "https://raw.githubusercontent.com/$Repository/$ReleaseTag/icon.png"
$repoEntry['DownloadLinkInstall'] = $downloadUrl
$repoEntry['DownloadLinkUpdate'] = $downloadUrl
$repoEntry['DownloadLinkTesting'] = $downloadUrl
$repoEntry['DownloadCount'] = 0
$repoEntry['LastUpdate'] = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$repoPath = Join-Path $artifacts 'repo.json'
[System.IO.File]::WriteAllText($repoPath, (ConvertTo-Json -InputObject @($repoEntry) -Depth 32) + "`n", $utf8)

$checksumPath = Join-Path $artifacts 'SHA256SUMS'
$checksumLines = foreach ($name in @('latest.zip', 'repo.json')) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $artifacts $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $name"
}
[System.IO.File]::WriteAllText($checksumPath, ($checksumLines -join "`n") + "`n", $utf8)

Write-Host "Validated $pluginName $version (Dalamud API 15, x64); packaged four files."
[pscustomobject]@{
    Version = $version
    ReleaseTag = $ReleaseTag
    PackageDirectory = $packageDirectory
    ZipPath = $zipPath
    RepositoryPath = $repoPath
    ChecksumPath = $checksumPath
}
