[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
try {
    $manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'latest.json') -Raw | ConvertFrom-Json
    & (Join-Path $PSScriptRoot 'Install-CmnCadTranslator.ps1') `
        -PackagePath (Join-Path $PSScriptRoot 'CmnCadTranslator.bundle.zip') `
        -ExpectedVersion $manifest.version
    & (Join-Path $PSScriptRoot 'Activate-Licence.ps1')
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
