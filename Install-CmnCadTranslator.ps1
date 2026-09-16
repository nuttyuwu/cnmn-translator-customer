<#
.SYNOPSIS
    Installs the latest CN-MN AutoCAD Translator release for the current user.

.DESCRIPTION
    Downloads the latest public GitHub Release, verifies its SHA-256 checksum,
    installs the Autodesk application bundle under the current user's roaming
    profile and preserves an existing glossary and settings. Updates are manual:
    run this installer again after a new release is published.

    AutoCAD must be closed while the bundle is installed or updated.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-CmnCadTranslator.ps1
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:APPDATA 'Autodesk\ApplicationPlugins'),
    [string]$AutoCadProcessName = 'acad',
    [string]$PackagePath,
    [string]$ChecksumPath,
    [string]$ExpectedVersion,
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'

# Invoke-WebRequest's own progress bar throttles the transfer badly on Windows
# PowerShell 5.1, so it stays suppressed for the small checksum fetch. The
# bundle is streamed by Save-ReleaseAsset below, which reports its own progress.
$ProgressPreference = 'SilentlyContinue'

$repository = 'nuttyuwu/cnmn-translator-customer'
$assetName = 'CmnCadTranslator.bundle.zip'
$checksumName = "$assetName.sha256"
if (-not $PackagePath -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot $assetName))) {
    $PackagePath = Join-Path $PSScriptRoot $assetName
    if (-not $ExpectedVersion) {
        $localManifest = Join-Path $PSScriptRoot 'latest.json'
        if (Test-Path -LiteralPath $localManifest) {
            $ExpectedVersion = (Get-Content -LiteralPath $localManifest -Raw | ConvertFrom-Json).version
        }
    }
}
$installRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$installPath = Join-Path $installRoot 'CmnCadTranslator.bundle'
$backupPath = Join-Path $installRoot 'CmnCadTranslator.bundle.rollback'
$tempRoot = Join-Path $installRoot ('.cnmn-install-' + [Guid]::NewGuid().ToString('N'))

function Get-ReleaseAsset([object]$release, [string]$name) {
    $asset = $release.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $asset) { throw "GitHub Release $($release.tag_name) is missing $name." }
    return $asset
}

function Save-ReleaseAsset {
    <#
        Streams a release asset to disk, reporting progress as bytes arrive.

        The bundle is ~66 MB and the link to GitHub is often slow, so a silent
        download looks indistinguishable from a hung installer. This reads the
        response in chunks and reports after each one.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [hashtable]$Headers = @{},
        [long]$ExpectedBytes = 0,
        [string]$Activity = 'Downloading'
    )

    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = 'GET'
    $request.Timeout = 60000            # connect
    $request.ReadWriteTimeout = 300000  # stalled mid-transfer
    foreach ($name in $Headers.Keys) {
        # User-Agent is a restricted header and must go through the property.
        if ($name -eq 'User-Agent') { $request.UserAgent = $Headers[$name] }
        else { $request.Headers[$name] = $Headers[$name] }
    }

    $response = $request.GetResponse()
    try {
        $total = if ($ExpectedBytes -gt 0) { $ExpectedBytes } else { $response.ContentLength }
        $totalMb = if ($total -gt 0) { $total / 1MB } else { 0 }
        $source = $response.GetResponseStream()
        $target = [System.IO.File]::Create($OutFile)
        try {
            $buffer = New-Object byte[] 131072
            $received = 0L
            $lastPercent = -1
            $lastWrite = [DateTime]::UtcNow
            while (($count = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $target.Write($buffer, 0, $count)
                $received += $count

                # Repaint on a percent change, or every second when the total is
                # unknown, so a slow link still shows movement.
                $percent = if ($total -gt 0) { [int](100 * $received / $total) } else { -1 }
                $elapsed = ([DateTime]::UtcNow - $lastWrite).TotalSeconds
                if ($percent -ne $lastPercent -or $elapsed -ge 1) {
                    $lastPercent = $percent
                    $lastWrite = [DateTime]::UtcNow
                    $status = if ($total -gt 0) {
                        '{0:N1} MB of {1:N1} MB' -f ($received / 1MB), $totalMb
                    } else {
                        '{0:N1} MB' -f ($received / 1MB)
                    }
                    if ($percent -ge 0) {
                        Write-Progress -Activity $Activity -Status $status -PercentComplete $percent
                    } else {
                        Write-Progress -Activity $Activity -Status $status
                    }
                }
            }
        } finally {
            $target.Dispose()
            $source.Dispose()
        }
        Write-Progress -Activity $Activity -Completed
        Write-Host ("  {0} - {1:N1} MB downloaded." -f $Activity, ((Get-Item -LiteralPath $OutFile).Length / 1MB))
    } finally {
        $response.Dispose()
    }
}

function Copy-UserData([string]$fromBundle, [string]$toBundle) {
    $relativePaths = @(
        'Contents\Engine\cnmn-settings.json',
        'Contents\Engine\glossary-added.csv',
        'Contents\Engine\glossary-candidates.csv'
    )
    foreach ($relative in $relativePaths) {
        $source = Join-Path $fromBundle $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        $destination = Join-Path $toBundle $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
    foreach ($extension in @('xlsx', 'csv')) {
        $legacyRelative = "Contents\Engine\glossary-legacy.$extension"
        $currentRelative = "Contents\Engine\glossary.$extension"
        $legacySource = Join-Path $fromBundle $legacyRelative
        $currentSource = Join-Path $fromBundle $currentRelative
        $destination = Join-Path $toBundle $legacyRelative
        if (Test-Path -LiteralPath $legacySource -PathType Leaf) {
            Copy-Item -LiteralPath $legacySource -Destination $destination -Force
        } elseif (Test-Path -LiteralPath $currentSource -PathType Leaf) {
            Copy-Item -LiteralPath $currentSource -Destination $destination -Force
        }
    }
}

function Assert-SafeArchive([string]$path) {
    $length = (Get-Item -LiteralPath $path).Length
    if ($length -le 0 -or $length -gt 500MB) { throw 'Release archive size is outside the accepted range.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($path)
    try {
        if ($archive.Entries.Count -le 0 -or $archive.Entries.Count -gt 2000) {
            throw 'Release archive contains an unsafe number of entries.'
        }
        [long]$total = 0
        $names = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $hasManifest = $false
        $hasEngine = $false
        $hasPlugin = $false
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            $parts = $name.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
            if ($name.StartsWith('/') -or $name.Contains(':') -or $parts -contains '..' -or $parts -contains '.') {
                throw 'Release archive contains an unsafe path.'
            }
            if ($parts | Where-Object { $_.EndsWith('.') -or $_.EndsWith(' ') }) {
                throw 'Release archive contains a Windows-ambiguous path.'
            }
            $normalized = $parts -join '/'
            if ($normalized -ine 'CmnCadTranslator.bundle' -and -not $normalized.StartsWith('CmnCadTranslator.bundle/', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'Release archive contains content outside the canonical bundle root.'
            }
            if (-not $names.Add($normalized)) { throw 'Release archive contains duplicate paths.' }
            if ([long]$entry.Length -gt 256MB) { throw 'Release archive contains an oversized entry.' }
            $total += [long]$entry.Length
            if ($total -gt 512MB) { throw 'Release archive expands beyond the accepted size limit.' }
            if ($normalized -ieq 'CmnCadTranslator.bundle/PackageContents.xml') { $hasManifest = $true }
            if ($normalized -ieq 'CmnCadTranslator.bundle/Contents/Engine/cnmn-engine.exe') { $hasEngine = $true }
            if ($normalized -ilike 'CmnCadTranslator.bundle/Contents/Windows/*/CmnCadTranslator.dll') { $hasPlugin = $true }
        }
        if (-not ($hasManifest -and $hasEngine -and $hasPlugin)) {
            throw 'Release archive is missing a required bundle executable.'
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Restore-PreviousBundle {
    if (Test-Path -LiteralPath $installPath) {
        Remove-Item -LiteralPath $installPath -Recurse -Force
    }
    if (Test-Path -LiteralPath $backupPath) {
        Move-Item -LiteralPath $backupPath -Destination $installPath
    }
}

try {
    New-Item -ItemType Directory -Force -Path $installRoot | Out-Null

    # Recovery changes the live autoloader path, so it obeys the same process
    # guard as a new installation.
    if (Get-Process -Name $AutoCadProcessName -ErrorAction SilentlyContinue) {
        throw 'AutoCAD is running. Close every AutoCAD window, then run this installer again.'
    }

    # Recover from an interrupted earlier activation before doing any network work.
    if (-not $VerifyOnly -and (-not (Test-Path -LiteralPath $installPath)) -and (Test-Path -LiteralPath $backupPath)) {
        Move-Item -LiteralPath $backupPath -Destination $installPath
    }

    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    if ($PackagePath) {
        if ($ExpectedVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Local packages require -ExpectedVersion MAJOR.MINOR.PATCH.' }
        $releaseVersion = $ExpectedVersion
        $packageSource = [IO.Path]::GetFullPath($PackagePath)
        if (-not $ChecksumPath) { $ChecksumPath = $packageSource + '.sha256' }
        $checksumSource = [IO.Path]::GetFullPath($ChecksumPath)
        $zipPath = Join-Path $tempRoot $assetName
        $checksumPath = Join-Path $tempRoot $checksumName
        $packageLength = (Get-Item -LiteralPath $packageSource).Length
        if ($packageLength -le 0 -or $packageLength -gt 500MB) { throw 'Local package size is outside the accepted range.' }
        Copy-Item -LiteralPath $packageSource -Destination $zipPath
        Copy-Item -LiteralPath $checksumSource -Destination $checksumPath
    } else {
    Write-Host "Checking https://github.com/$repository/releases/latest ..."
    $headers = @{ 'User-Agent' = 'CmnCadTranslator-Installer/0.3.0' }
    $release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$repository/releases/latest"
    if ([string]$release.tag_name -notmatch '^v(\d+\.\d+\.\d+)$') {
        throw "Latest release tag '$($release.tag_name)' is not a supported semantic version."
    }
    $releaseVersion = $Matches[1]
    $bundleAsset = Get-ReleaseAsset $release $assetName
    $checksumAsset = Get-ReleaseAsset $release $checksumName
    $maximumBundleBytes = 500MB
    if ([long]$bundleAsset.size -le 0 -or [long]$bundleAsset.size -gt $maximumBundleBytes) {
        throw "Release bundle size $($bundleAsset.size) is outside the accepted range."
    }

    $zipPath = Join-Path $tempRoot $assetName
    $checksumPath = Join-Path $tempRoot $checksumName
    Write-Host ("Downloading {0} ({1:N1} MB) from release {2} ..." -f `
        $assetName, ([long]$bundleAsset.size / 1MB), $release.tag_name)
    Save-ReleaseAsset -Uri $bundleAsset.browser_download_url -OutFile $zipPath `
        -Headers $headers -ExpectedBytes ([long]$bundleAsset.size) -Activity "Downloading $assetName"

    # The checksum is a few dozen bytes; a progress bar would only flicker.
    Invoke-WebRequest -Headers $headers -Uri $checksumAsset.browser_download_url -OutFile $checksumPath
    Write-Host 'Verifying checksum ...'
    if ((Get-Item -LiteralPath $zipPath).Length -ne [long]$bundleAsset.size) {
        throw 'Downloaded release bundle size does not match GitHub release metadata.'
    }
    }

    $checksumText = (Get-Content -LiteralPath $checksumPath -Raw).Trim()
    if ($checksumText -notmatch '^([0-9a-fA-F]{64})(?:\s+\*?CmnCadTranslator\.bundle\.zip)?$') {
        throw 'Invalid checksum file.'
    }
    $expectedHash = $Matches[1].ToLowerInvariant()
    $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "SHA-256 verification failed. Expected $expectedHash but downloaded $actualHash."
    }
    Assert-SafeArchive $zipPath

    $extractRoot = Join-Path $tempRoot 'extracted'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
    $sourceBundle = Join-Path $extractRoot 'CmnCadTranslator.bundle'
    $manifestPath = Join-Path $sourceBundle 'PackageContents.xml'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'The verified release archive does not contain CmnCadTranslator.bundle\PackageContents.xml.'
    }
    [xml]$sourceManifest = Get-Content -LiteralPath $manifestPath
    if ([string]$sourceManifest.ApplicationPackage.AppVersion -ne $releaseVersion) {
        throw 'The bundle AppVersion does not match the expected release version.'
    }

    if ($VerifyOnly) {
        Write-Host "Verified CN-MN AutoCAD Translator $releaseVersion; no bundle installed."
        return
    }

    if (Test-Path -LiteralPath $installPath) {
        Copy-UserData $installPath $sourceBundle
    }

    # Close the race between the first process check and bundle activation.
    if (Get-Process -Name $AutoCadProcessName -ErrorAction SilentlyContinue) {
        throw 'AutoCAD started while the release was downloading. Close AutoCAD and run the installer again.'
    }

    if (Test-Path -LiteralPath $backupPath) {
        Remove-Item -LiteralPath $backupPath -Recurse -Force
    }
    if (Test-Path -LiteralPath $installPath) {
        Move-Item -LiteralPath $installPath -Destination $backupPath
    }

    try {
        Move-Item -LiteralPath $sourceBundle -Destination $installPath
    }
    catch {
        Restore-PreviousBundle
        throw
    }

    Write-Host "Installed CN-MN AutoCAD Translator $releaseVersion" -ForegroundColor Green
    Write-Host "Location: $installPath"
    Write-Host 'Updates are manual. Close AutoCAD and run this installer again for a newer release.'
    Write-Host "Previous bundle retained for rollback: $backupPath"
    Write-Host 'Start AutoCAD and choose Always Load once if AutoCAD asks about the unsigned plug-in.'
    Write-Host 'Then run MNABOUT.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
