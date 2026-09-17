[CmdletBinding()]
param([switch]$Force, [switch]$WhatIf, [string]$DataRoot = $env:APPDATA,
    [string]$AutoCadProcessName = 'acad', [string]$EngineProcessName = 'cnmn-engine')
$ErrorActionPreference = 'Stop'
$data = [IO.Path]::GetFullPath($DataRoot).TrimEnd('\','/')
$plugins = Join-Path $data 'Autodesk\ApplicationPlugins'
$productData = Join-Path $data 'CmnCadTranslator'
$targets = @((Join-Path $plugins 'CmnCadTranslator.bundle'),
    (Join-Path $plugins 'CmnCadTranslator.bundle.rollback'),
    $productData)
if (Test-Path -LiteralPath $plugins -PathType Container) {
    $targets += @(Get-ChildItem -LiteralPath $plugins -Force | Where-Object {
        $_.Name -match '^(CmnCadTranslator\.bundle\.failed-|\.cnmn-install-)[0-9a-f]{32}$'
    } | ForEach-Object { $_.FullName })
}
# Validate every deletion path and reject links before any data is touched.
foreach ($target in $targets) {
    $resolved = [IO.Path]::GetFullPath($target)
    if (-not $resolved.StartsWith($data + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe uninstall target.' }
    $ancestor = $resolved
    while ($ancestor) {
        if ((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Uninstall refuses linked directories. Remove the link explicitly first.' }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    if (Test-Path -LiteralPath $resolved) {
        if (Get-ChildItem -LiteralPath $resolved -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'Uninstall refuses linked content.' }
    }
}
if (Get-Process -Name $AutoCadProcessName,$EngineProcessName -ErrorAction SilentlyContinue) { throw 'Close AutoCAD and the translator before uninstalling.' }
if (-not $Force -and -not $WhatIf) {
    Add-Type -AssemblyName System.Windows.Forms
    $answer = [Windows.Forms.MessageBox]::Show('Remove MN Translator and ALL its local data? This deletes the licence, saved Qwen key, settings, logs and local glossaries. Export any glossary you want to keep first.', 'Uninstall MN Translator', 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }
}
if ($WhatIf) { foreach ($target in $targets) { Write-Host "Would remove: $target" }; return }
# The UI confirmation above is the single confirmation for this operation.
foreach ($target in $targets) {
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force -Confirm:$false }
}
# Remove app/provider credential variables from this user, never machine-wide.
# A synthetic DataRoot used in tests must never change the actual user's environment.
if ($data -eq [IO.Path]::GetFullPath($env:APPDATA).TrimEnd('\','/')) {
    $customLicence = [Environment]::GetEnvironmentVariable('CNMN_LICENCE', 'User')
    if ($customLicence -and (Test-Path -LiteralPath $customLicence)) {
        Write-Warning 'A custom licence file outside the standard data folder remains. Delete your custom CNMN_LICENCE file separately if no longer needed.'
    }
    foreach ($name in @('CNMN_QWEN_API_KEY','DASHSCOPE_API_KEY','CNMN_LICENCE','CNMN_UPDATE_MANIFEST','CNMN_ENGINE','CNMN_ENGINE_TIMEOUT_SECONDS')) {
        [Environment]::SetEnvironmentVariable($name, $null, 'User')
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    $legacyTask = Get-ScheduledTask -TaskName 'CN-MN AutoCAD Translator Update' -ErrorAction SilentlyContinue
    foreach ($task in $legacyTask) {
        if ($task.Principal.UserId -in @([Security.Principal.WindowsIdentity]::GetCurrent().Name, [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)) {
            $task | Unregister-ScheduledTask -Confirm:$false -ErrorAction Stop
        }
    }
}
Write-Host 'MN Translator, its local licence/data and saved Qwen credential have been removed.'
