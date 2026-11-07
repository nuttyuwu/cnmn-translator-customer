[CmdletBinding()]
param([switch]$Force, [switch]$WhatIf, [string]$DataRoot = $env:APPDATA,
    [string]$LocalDataRoot = '', [string]$DesktopRoot = '',
    [string]$AutoCadProcessName = 'acad', [string]$EngineProcessName = 'cnmn-engine',
    [string]$ManagerProcessName = 'CMNSetup', [string]$UpdaterProcessName = 'CMNUpdater')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

function Full-Root([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^(?:[a-zA-Z]:[\\/]|\\\\[^\\]+\\[^\\]+)') {
        throw 'Uninstall roots must be explicit absolute directories.'
    }
    return [IO.Path]::GetFullPath($Path).TrimEnd('\','/')
}
function Assert-Unlinked([string]$Path, [switch]$AncestorsOnly) {
    $ancestor = $Path
    while ($ancestor) {
        $item = Get-Item -LiteralPath $ancestor -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Uninstall refuses linked directories or files. Remove the link explicitly first.'
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    if ($AncestorsOnly) { return }
    # Visit children one level at a time: never traverse a junction before rejecting it.
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($Path)
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        if (Test-Path -LiteralPath $current -PathType Container) {
            foreach ($item in Get-ChildItem -LiteralPath $current -Force) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Uninstall refuses linked content.' }
                if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            }
        }
    }
}

$liveData = Full-Root $env:APPDATA
$liveLocal = Full-Root ([Environment]::GetFolderPath('LocalApplicationData'))
$liveDesktop = Full-Root ([Environment]::GetFolderPath('DesktopDirectory'))
$data = Full-Root $DataRoot
$sandbox = $data -ne $liveData
# A synthetic DataRoot also isolates the newer local-data and desktop locations.
if (-not $LocalDataRoot) { $LocalDataRoot = if ($sandbox) { Join-Path $data 'LocalAppData' } else { $liveLocal } }
if (-not $DesktopRoot) { $DesktopRoot = if ($sandbox) { Join-Path $data 'Desktop' } else { $liveDesktop } }
$localData = Full-Root $LocalDataRoot
$desktop = Full-Root $DesktopRoot
if ($sandbox -and ($localData -eq $liveLocal -or $desktop -eq $liveDesktop)) {
    throw 'A synthetic DataRoot cannot target the real local-data or desktop folder.'
}
$plugins = Join-Path $data 'Autodesk\ApplicationPlugins'
$productData = Join-Path $data 'CmnCadTranslator'
$localProduct = Join-Path $localData 'CmnCadTranslator'
$managerRoot = Join-Path $localProduct 'Manager'
$shortcut = Join-Path $desktop 'CMN Translator Manager.lnk'
$targets = @(
    @{ Path = Join-Path $plugins 'CmnCadTranslator.bundle'; Root = $data },
    @{ Path = Join-Path $plugins 'CmnCadTranslator.bundle.rollback'; Root = $data },
    @{ Path = $productData; Root = $data },
    @{ Path = $localProduct; Root = $localData },
    @{ Path = $shortcut; Root = $desktop }
)
# Check the plugin parent before enumeration, including when no bundle exists yet.
Assert-Unlinked $plugins -AncestorsOnly
if (Test-Path -LiteralPath $plugins -PathType Container) {
    foreach ($item in Get-ChildItem -LiteralPath $plugins -Force) {
        if ($item.Name -match '^(CmnCadTranslator\.bundle\.failed-|\.cnmn-install-|\.cnmn-incoming-|\.cnmn-previous-)[0-9a-f]{32}$') {
            $targets += @{ Path = $item.FullName; Root = $data }
        }
    }
}
# Validate the complete deletion plan before touching any data.
foreach ($target in $targets) {
    $resolved = [IO.Path]::GetFullPath($target.Path)
    if (-not $resolved.StartsWith($target.Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Unsafe uninstall target.'
    }
    Assert-Unlinked $resolved
}
if (Test-Path -LiteralPath $shortcut) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $null
    try {
        $link = $shell.CreateShortcut($shortcut)
        $linkTarget = [string]$link.TargetPath
        if (-not $linkTarget -or -not [IO.Path]::GetFullPath($linkTarget).StartsWith($managerRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'An unrelated desktop shortcut uses the manager name. Rename it before uninstalling.'
        }
    } finally {
        if ($link) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link) }
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
    }
}
if (Get-Process -Name $AutoCadProcessName,$EngineProcessName,$ManagerProcessName,$UpdaterProcessName -ErrorAction SilentlyContinue) {
    throw 'Close AutoCAD, the translator, CMN Translator Manager and its updater before uninstalling.'
}
if (-not $Force -and -not $WhatIf) {
    Add-Type -AssemblyName System.Windows.Forms
    $answer = [Windows.Forms.MessageBox]::Show('Remove CMN Translator and ALL its local data? This deletes local glossaries, settings, run history, caches, saved credentials, updater tokens, backups, the manager and its desktop shortcut. Export any glossary you want to keep first.', 'Uninstall CMN Translator', 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }
}
if ($WhatIf) { foreach ($target in $targets) { Write-Host "Would remove: $($target.Path)" }; return }
if (Get-Process -Name $AutoCadProcessName,$EngineProcessName,$ManagerProcessName,$UpdaterProcessName -ErrorAction SilentlyContinue) {
    throw 'Close AutoCAD, the translator, CMN Translator Manager and its updater before uninstalling.'
}
foreach ($target in $targets) {
    # Recheck before each deletion in case paths changed while confirmation was open.
    Assert-Unlinked $target.Path
    if (Test-Path -LiteralPath $target.Path) { Remove-Item -LiteralPath $target.Path -Recurse -Force -Confirm:$false }
}
# Only a real, complete profile removal can change the user's saved variables/tasks.
if (-not $sandbox -and $localData -eq $liveLocal -and $desktop -eq $liveDesktop) {
    foreach ($name in @('CNMN_LICENCE','CNMN_DATA_DIRECTORY','CNMN_UPDATER_HOME')) {
        if ([Environment]::GetEnvironmentVariable($name, 'User')) {
            Write-Warning "$name points to custom data. Custom locations are not deleted; remove them separately if no longer needed."
        }
    }
    foreach ($name in @('CNMN_QWEN_API_KEY','DASHSCOPE_API_KEY','CNMN_LICENCE','CNMN_DATA_DIRECTORY',
        'CNMN_UPDATE_MANIFEST','CNMN_GLOSSARY_MANIFEST','CNMN_UPDATER_HOME','CNMN_ENGINE','CNMN_ENGINE_TIMEOUT_SECONDS')) {
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
Write-Host 'CMN Translator and its standard local data, credentials, manager and updater have been removed. External company/project glossaries are preserved.'
