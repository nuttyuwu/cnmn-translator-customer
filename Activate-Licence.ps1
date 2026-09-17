[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$engine = Join-Path $env:APPDATA 'Autodesk\ApplicationPlugins\CmnCadTranslator.bundle\Contents\Engine\cnmn-engine.exe'
$adjacentEngine = Join-Path $PSScriptRoot '..\Engine\cnmn-engine.exe'
if (Test-Path -LiteralPath $adjacentEngine -PathType Leaf) { $engine = [IO.Path]::GetFullPath($adjacentEngine) }
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw 'Run Install.cmd first.' }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$licence = (& $engine licence status | Out-String) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Cannot read licence status.' }
$form = New-Object Windows.Forms.Form
$form.Text = 'MN Translator - Activation and Qwen setup'
$form.ClientSize = New-Object Drawing.Size(580, 705)
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
$instructions.Text = 'Paste the activation key you received, then click Activate.'
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
# Credentials go through stdin, never command-line arguments or plaintext files.
function Invoke-QwenSetup([string]$action, [string]$payload = '') {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $engine; $start.Arguments = "qwen $action"
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $output = $process.StandardOutput.ReadToEndAsync()
        $errorOutput = $process.StandardError.ReadToEndAsync()
        if ($payload) { $process.StandardInput.Write($payload) }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Qwen setup timed out. Check the connection and try again.' }
        $message = ($output.Result + $errorOutput.Result).Trim()
        if ($process.ExitCode -ne 0) { throw $message }
        return $message
    } finally { $process.Dispose() }
}
function Add-QwenLabel([string]$caption, [int]$top) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $caption; $label.SetBounds(20,$top,130,24); $form.Controls.Add($label)
}
Add-QwenLabel 'Qwen API key' 410
$apiKey = New-Object Windows.Forms.TextBox
$apiKey.UseSystemPasswordChar = $true; $apiKey.MaxLength = 4096
$apiKey.SetBounds(155,407,405,26); $form.Controls.Add($apiKey)
Add-QwenLabel 'Region' 450
$region = New-Object Windows.Forms.ComboBox
$region.DropDownStyle = 'DropDownList'; $region.SetBounds(155,447,405,26)
[void]$region.Items.AddRange(@('Singapore','Beijing','Custom workspace endpoint'))
$region.SelectedIndex = 0; $form.Controls.Add($region)
Add-QwenLabel 'API endpoint' 490
$endpoint = New-Object Windows.Forms.TextBox
$endpoint.SetBounds(155,487,405,26); $endpoint.Text = 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1'
$endpoint.ReadOnly = $true; $form.Controls.Add($endpoint)
$region.Add_SelectedIndexChanged({
    $endpoint.ReadOnly = $region.SelectedIndex -ne 2
    if ($region.SelectedIndex -eq 0) { $endpoint.Text = 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1' }
    elseif ($region.SelectedIndex -eq 1) { $endpoint.Text = 'https://dashscope.aliyuncs.com/compatible-mode/v1' }
})
Add-QwenLabel 'Qwen model' 530
$model = New-Object Windows.Forms.TextBox
$model.Text = 'qwen-plus'; $model.SetBounds(155,527,405,26); $form.Controls.Add($model)
$saveQwen = New-Object Windows.Forms.Button
$saveQwen.Text = 'Save Qwen setup'; $saveQwen.SetBounds(20,572,185,36); $form.Controls.Add($saveQwen)
$testQwen = New-Object Windows.Forms.Button
$testQwen.Text = 'Check connection'; $testQwen.SetBounds(375,572,185,36); $form.Controls.Add($testQwen)
$qwenStatus = New-Object Windows.Forms.Label
$qwenStatus.Text = 'Key is encrypted for this Windows user. Choose the region where your key was issued.'
$qwenStatus.SetBounds(20,625,540,65); $form.Controls.Add($qwenStatus)
$saveQwen.Add_Click({
    try {
        $saveQwen.Enabled = $false; $testQwen.Enabled = $false
        $payload = @{ apiKey=$apiKey.Text.Trim(); endpoint=$endpoint.Text.Trim(); model=$model.Text.Trim() } | ConvertTo-Json -Compress
        $qwenStatus.Text = Invoke-QwenSetup 'save' $payload
        $apiKey.Clear(); $payload = $null
    } catch { $qwenStatus.Text = $_.Exception.Message }
    finally { $payload = $null; $saveQwen.Enabled = $true; $testQwen.Enabled = $true }
})
$testQwen.Add_Click({
    try {
        $saveQwen.Enabled = $false; $testQwen.Enabled = $false; $form.UseWaitCursor = $true
        $qwenStatus.Text = 'Checking Qwen API access (no drawing data is sent)...'; $form.Refresh()
        $qwenStatus.Text = Invoke-QwenSetup 'test'
    } catch { $qwenStatus.Text = $_.Exception.Message }
    finally { $saveQwen.Enabled = $true; $testQwen.Enabled = $true; $form.UseWaitCursor = $false }
})
try {
    $saved = (Invoke-QwenSetup 'status') | ConvertFrom-Json
    if ($saved.provider -eq 'qwen' -and $saved.endpoint) {
        $region.SelectedIndex = 2; $endpoint.Text = $saved.endpoint; $model.Text = $saved.model
        if ($saved.configured) { $qwenStatus.Text = 'A Qwen key is already saved. Check connection, or enter a replacement key and Save.' }
    }
} catch { $qwenStatus.Text = $_.Exception.Message }
try { [void]$form.ShowDialog() } finally { $form.Dispose() }
