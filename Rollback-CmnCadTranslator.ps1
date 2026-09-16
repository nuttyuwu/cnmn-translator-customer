<#
.SYNOPSIS
    Restores the previous CN-MN AutoCAD Translator bundle for the current user.

.DESCRIPTION
    AutoCAD must be closed. The script swaps the retained .rollback bundle back
    into service. It also removes any legacy scheduled-update task left by a
    pre-0.4 installation.
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:APPDATA 'Autodesk\ApplicationPlugins'),
    [string]$TaskName = 'CN-MN AutoCAD Translator Update',
    [string]$AutoCadProcessName = 'acad',
    [scriptblock]$MoveBundle = {
        param([string]$Source, [string]$Destination)
        Move-Item -LiteralPath $Source -Destination $Destination
    },
    [scriptblock]$CopyUserData = {
        param([string]$Source, [string]$Destination)
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
)

$ErrorActionPreference = 'Stop'
$installPath = Join-Path $InstallRoot 'CmnCadTranslator.bundle'
$rollbackPath = Join-Path $InstallRoot 'CmnCadTranslator.bundle.rollback'
$failedPath = Join-Path $InstallRoot ('CmnCadTranslator.bundle.failed-' + [Guid]::NewGuid().ToString('N'))
$userDataFiles = @('glossary.xlsx', 'glossary.csv', 'glossary-added.csv', 'glossary-candidates.csv', 'cnmn-settings.json')

if (Get-Process -Name $AutoCadProcessName -ErrorAction SilentlyContinue) {
    throw 'AutoCAD is running. Close every AutoCAD window, then run rollback again.'
}
if (-not (Test-Path -LiteralPath $rollbackPath -PathType Container)) {
    throw "No rollback bundle is available at $rollbackPath"
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$currentWasMoved = $false
try {
    if (Test-Path -LiteralPath $installPath) {
        & $MoveBundle $installPath $failedPath
        $currentWasMoved = $true
    }
    & $MoveBundle $rollbackPath $installPath

    $failedEngine = Join-Path $failedPath 'Contents\Engine'
    $restoredEngine = Join-Path $installPath 'Contents\Engine'
    foreach ($name in $userDataFiles) {
        $source = Join-Path $failedEngine $name
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            & $CopyUserData $source (Join-Path $restoredEngine $name)
        }
    }
}
catch {
    $originalError = $_
    $recoveryError = $null
    if ($currentWasMoved -and (Test-Path -LiteralPath $failedPath)) {
        try {
            # After a successful swap, $installPath is the restored rollback.
            # Put it back before restoring the failed current bundle so neither
            # version is destroyed and the rollback can be retried.
            if (Test-Path -LiteralPath $installPath) {
                if (Test-Path -LiteralPath $rollbackPath) {
                    throw "Cannot preserve the restored bundle because $rollbackPath already exists."
                }
                & $MoveBundle $installPath $rollbackPath
            }
            if (-not (Test-Path -LiteralPath $installPath)) {
                & $MoveBundle $failedPath $installPath
            }
        }
        catch {
            $recoveryError = $_
        }
    }
    if ($null -ne $recoveryError) {
        throw [AggregateException]::new(
            'Rollback failed and recovery could not restore the canonical paths; both bundle versions were preserved.',
            @($originalError.Exception, $recoveryError.Exception))
    }
    throw $originalError
}

if (Test-Path -LiteralPath $failedPath) {
    Remove-Item -LiteralPath $failedPath -Recurse -Force
}

[xml]$manifest = Get-Content -LiteralPath (Join-Path $installPath 'PackageContents.xml')
$version = [string]$manifest.ApplicationPackage.AppVersion
Write-Host "Restored CN-MN AutoCAD Translator $version" -ForegroundColor Green
Write-Host 'Any legacy automatic-update task is disabled. Install future releases manually.'
