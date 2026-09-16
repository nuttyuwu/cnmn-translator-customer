[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$engine = Join-Path $env:APPDATA 'Autodesk\ApplicationPlugins\CmnCadTranslator.bundle\Contents\Engine\cnmn-engine.exe'
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw 'Run Install.cmd first.' }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$licence = (& $engine licence status | Out-String) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Cannot read licence status.' }
$form = New-Object Windows.Forms.Form
$form.Text = 'MN Translator - Activate licence'
$form.ClientSize = New-Object Drawing.Size(580, 410)
$form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'; $form.AutoScaleMode = 'Font'
$status = New-Object Windows.Forms.Label
$status.Text = if ($licence.valid) { "Licensed to $($licence.customer). You can start AutoCAD." } else { 'Installed. A licence is required before you can translate.' }
$status.SetBounds(20, 18, 540, 40); $form.Controls.Add($status)
$hint = New-Object Windows.Forms.Label
$hint.Text = "Send this machine ID to $($licence.contact)."
$hint.SetBounds(20, 62, 540, 35); $form.Controls.Add($hint)
$machine = New-Object Windows.Forms.TextBox
$machine.Text = $licence.fingerprint; $machine.ReadOnly = $true
$machine.SetBounds(20, 101, 340, 26); $form.Controls.Add($machine)
$copy = New-Object Windows.Forms.Button
$copy.Text = 'Copy machine ID'; $copy.SetBounds(375, 99, 185, 30)
$copy.Add_Click({
    try { [Windows.Forms.Clipboard]::SetText($machine.Text) }
    catch { [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Could not copy') | Out-Null }
}); $form.Controls.Add($copy)
$instructions = New-Object Windows.Forms.Label
$instructions.Text = 'Paste the complete licence text you received, or open your .lic file.'
$instructions.SetBounds(20, 147, 540, 28); $form.Controls.Add($instructions)
$text = New-Object Windows.Forms.TextBox
$text.Multiline = $true; $text.ScrollBars = 'Vertical'; $text.MaxLength = 65536
$text.SetBounds(20, 181, 540, 145); $form.Controls.Add($text)
$browse = New-Object Windows.Forms.Button
$browse.Text = 'Open licence file...'; $browse.SetBounds(20, 346, 185, 36)
$browse.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    try {
        $dialog.Filter = 'Licence file (*.lic)|*.lic'
        if ($dialog.ShowDialog($form) -eq 'OK') {
            if ((Get-Item -LiteralPath $dialog.FileName).Length -gt 65536) { throw 'Licence file is too large.' }
            $text.Text = [IO.File]::ReadAllText($dialog.FileName)
        }
    } catch { [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Could not open licence') | Out-Null }
    finally { $dialog.Dispose() }
}); $form.Controls.Add($browse)
$activate = New-Object Windows.Forms.Button
$activate.Text = 'Activate'; $activate.SetBounds(375, 346, 185, 36)
$activate.Add_Click({
    $temporary = $null
    try {
        if ([string]::IsNullOrWhiteSpace($text.Text)) { throw 'Paste a licence or open the .lic file first.' }
        $temporary = [IO.Path]::GetTempFileName()
        [IO.File]::WriteAllText($temporary, $text.Text, [Text.UTF8Encoding]::new($false))
        $message = & $engine licence activate $temporary 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw $message.Trim() }
        $status.Text = $message.Trim() + ' Start AutoCAD and run MNTRANSLATE.'
        $text.Clear()
        [Windows.Forms.MessageBox]::Show($form, $status.Text, 'Activated') | Out-Null
    } catch { [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Licence not accepted') | Out-Null }
    finally { if ($temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}); $form.Controls.Add($activate)
try { [void]$form.ShowDialog() } finally { $form.Dispose() }
