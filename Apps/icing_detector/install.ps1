param(
    [ValidateSet('auto', 'cpu', 'cuda')][string]$Device = 'auto',
    [string]$Proxy = '',
    [switch]$LaunchAfterInstall,
    [switch]$AutoStart,
    [switch]$CloseOnSuccess,
    [string]$CaptureDirectory = '',
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Images
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
[Windows.Forms.Application]::SetUnhandledExceptionMode('ThrowException')
$appRoot = $PSScriptRoot
$runtimeRoot = Join-Path $appRoot '.runtime'
New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
$pathHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($appRoot.ToLowerInvariant()))).Replace('-', '').Substring(0, 16)
$created = $false
$instance = [Threading.Mutex]::new($true, "Local\IcingInstaller_$pathHash", [ref]$created)
if (-not $created) {
    [Windows.Forms.MessageBox]::Show('安装向导已经打开，请切换到现有窗口。', 'Aircraft Icing') | Out-Null
    $instance.Dispose()
    exit 1
}
$script:worker = $null
$script:success = $false
$script:busy = $false
$script:resultCode = 1
$statusPath = Join-Path $runtimeRoot 'install-status.json'
$outputPath = Join-Path $runtimeRoot 'install-output.log'
$errorPath = Join-Path $runtimeRoot 'install-error.log'
$ink = [Drawing.ColorTranslator]::FromHtml('#202835')
$muted = [Drawing.ColorTranslator]::FromHtml('#647085')
$accent = [Drawing.ColorTranslator]::FromHtml('#1477e5')
$green = [Drawing.ColorTranslator]::FromHtml('#218569')
$red = [Drawing.ColorTranslator]::FromHtml('#b84843')
$form = [Windows.Forms.Form]::new()
$form.Text = 'Aircraft Icing · 安装与修复'
$form.ClientSize = [Drawing.Size]::new(780, [Math]::Min(730, [Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 90))
$form.MinimumSize = [Drawing.Size]::new(720, 640)
$form.StartPosition = 'CenterScreen'
$form.AutoScaleMode = 'Dpi'
$form.AutoScaleDimensions = [Drawing.SizeF]::new(96, 96)
$form.Font = [Drawing.Font]::new('Microsoft YaHei UI', 9)
$form.BackColor = [Drawing.Color]::White
$form.ForeColor = $ink
$form.MaximizeBox = $false
function Add-Label([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height, [single]$Size = 9, [Drawing.Color]$Color = $ink) {
    $label = [Windows.Forms.Label]::new()
    $label.Text = $Text
    $label.Location = [Drawing.Point]::new($X, $Y)
    $label.Size = [Drawing.Size]::new($Width, $Height)
    $label.Font = [Drawing.Font]::new('Microsoft YaHei UI', $Size)
    $label.ForeColor = $Color
    $label.Anchor = 'Top, Left, Right'
    $form.Controls.Add($label)
    return $label
}
$title = Add-Label 'Aircraft Icing Detecion Studio 安装向导' 28 23 700 40 18
$title.Font = [Drawing.Font]::new('Microsoft YaHei UI', 18, [Drawing.FontStyle]::Bold)
$null = Add-Label '自动检查并准备 Python、依赖和模型。已有可用环境会直接复用。' 30 70 700 25 9 $muted
$null = Add-Label '计算模式' 30 147 95 25
$deviceCombo = [Windows.Forms.ComboBox]::new()
$deviceCombo.DropDownStyle = 'DropDownList'
$deviceCombo.Items.AddRange(@('自动选择（推荐）', 'CPU（下载较小）', 'NVIDIA GPU'))
$deviceCombo.SelectedIndex = @('auto', 'cpu', 'cuda').IndexOf($Device)
$deviceCombo.Location = [Drawing.Point]::new(130, 142)
$deviceCombo.Size = [Drawing.Size]::new(240, 30)
$form.Controls.Add($deviceCombo)
$null = Add-Label 'GPU 运行库较大；自动模式可在失败后转用 CPU。' 386 148 355 35 8 $muted
$null = Add-Label '网络代理' 30 190 100 25
$proxyBox = [Windows.Forms.TextBox]::new()
$proxyBox.Text = $Proxy
$proxyBox.Location = [Drawing.Point]::new(130, 185)
$proxyBox.Size = [Drawing.Size]::new(370, 30)
$proxyBox.Anchor = 'Top, Left, Right'
$form.Controls.Add($proxyBox)
$null = Add-Label '可选：http://127.0.0.1:7890' 510 190 240 25 8 $muted
$heading = Add-Label '准备就绪' 28 235 700 32 16
$message = Add-Label '点击“开始安装”。首次下载需要网络，过程中可以查看下方详情。' 30 274 700 43 9 $muted
$script:completedSteps = 0
$progress = [Windows.Forms.Panel]::new()
$progress.Location = [Drawing.Point]::new(30, 319)
$progress.Size = [Drawing.Size]::new(720, 7)
$progress.Anchor = 'Top, Left, Right'
$progress.BackColor = [Drawing.ColorTranslator]::FromHtml('#e7ebf0')
$progressFill = [Windows.Forms.Panel]::new()
$progressFill.BackColor = $accent
$progressFill.Size = [Drawing.Size]::new(0, 7)
$progress.Controls.Add($progressFill)
$progress.Add_Resize({ $progressFill.Width = [int]($progress.ClientSize.Width * $script:completedSteps / 5) })
$form.Controls.Add($progress)
$stepLabels = @()
$stepNames = @('检查项目和模型', '准备 Python 3.12', '创建本机运行环境', '安装应用依赖', '验证模型加载')
for ($i = 0; $i -lt $stepNames.Count; $i++) {
    $stepLabels += Add-Label ("○  " + $stepNames[$i]) 30 (342 + $i * 22) 700 22 9 $muted
}
$null = Add-Label '安装详情' 30 463 400 23 9 $muted
$details = [Windows.Forms.TextBox]::new()
$details.Multiline = $true
$details.ReadOnly = $true
$details.ScrollBars = 'Vertical'
$details.Font = [Drawing.Font]::new('Consolas', 8)
$details.BackColor = [Drawing.ColorTranslator]::FromHtml('#f5f6f8')
$details.BorderStyle = 'FixedSingle'
$details.Location = [Drawing.Point]::new(30, 490)
$details.Size = [Drawing.Size]::new(720, [Math]::Max(55, $form.ClientSize.Height - 580))
$details.Anchor = 'Top, Bottom, Left, Right'
$details.Text = '将在这里显示真实下载进度、安装输出和检查结果。'
$form.Controls.Add($details)
$openLogs = [Windows.Forms.LinkLabel]::new()
$openLogs.Text = '打开日志文件夹'
$openLogs.Location = [Drawing.Point]::new(30, $form.ClientSize.Height - 50)
$openLogs.Size = [Drawing.Size]::new(175, 25)
$openLogs.Anchor = 'Bottom, Left'
$openLogs.LinkColor = $accent
$openLogs.Add_LinkClicked({ Start-Process -FilePath explorer.exe -ArgumentList ('"{0}"' -f $runtimeRoot) })
$form.Controls.Add($openLogs)
$cancel = [Windows.Forms.Button]::new()
$cancel.Text = '关闭'
$cancel.Location = [Drawing.Point]::new($form.ClientSize.Width - 270, $form.ClientSize.Height - 60)
$cancel.Size = [Drawing.Size]::new(100, 37)
$cancel.Anchor = 'Bottom, Right'
$form.Controls.Add($cancel)
$primary = [Windows.Forms.Button]::new()
$primary.Text = '开始安装'
$primary.Location = [Drawing.Point]::new($form.ClientSize.Width - 155, $form.ClientSize.Height - 60)
$primary.Size = [Drawing.Size]::new(125, 37)
$primary.Anchor = 'Bottom, Right'
$primary.FlatStyle = 'Flat'
$primary.FlatAppearance.BorderSize = 0
$primary.BackColor = $accent
$primary.ForeColor = [Drawing.Color]::White
$form.Controls.Add($primary)
$form.AcceptButton = $primary
$form.CancelButton = $cancel
function Start-App {
    $appArguments = @('-X', 'utf8', ('"{0}"' -f (Join-Path $appRoot 'app.py')))
    foreach ($image in $Images) { $appArguments += ('"{0}"' -f $image) }
    Start-Process -FilePath (Join-Path $appRoot '.venv\Scripts\pythonw.exe') -ArgumentList $appArguments -WorkingDirectory $appRoot -WindowStyle Hidden
}
function Save-InstallerImage([string]$Name) {
    if (-not $CaptureDirectory) { return }
    New-Item -ItemType Directory -Force -Path $CaptureDirectory | Out-Null
    $bitmap = [Drawing.Bitmap]::new($form.Width, $form.Height)
    try {
        $form.DrawToBitmap($bitmap, [Drawing.Rectangle]::new(0, 0, $form.Width, $form.Height))
        $bitmap.Save((Join-Path $CaptureDirectory $Name), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
}
function Trace-Installer([string]$Text) {
    if ($CaptureDirectory) {
        New-Item -ItemType Directory -Force -Path $CaptureDirectory | Out-Null
        [IO.File]::AppendAllText((Join-Path $CaptureDirectory 'ui-trace.log'), $Text + "`r`n")
    }
}
function Stop-Worker {
    if ($script:worker -and -not $script:worker.HasExited) {
        # This process was created by this installer; terminate only its process tree.
        & taskkill.exe /PID $script:worker.Id /T /F *> $null
        $script:worker.WaitForExit(5000) | Out-Null
    }
    $script:busy = $false
}
function Start-Install {
    Trace-Installer 'Starting worker'
    $script:success = $false
    $script:busy = $true
    $primary.Enabled = $false
    $deviceCombo.Enabled = $false
    $proxyBox.Enabled = $false
    $cancel.Text = '取消安装'
    $heading.Text = '正在准备'
    $heading.ForeColor = $ink
    $message.Text = '安装任务正在后台运行，请保持网络连接。'
    $script:completedSteps = 0
    $progressFill.Width = 0
    $progressFill.BackColor = $accent
    foreach ($label in $stepLabels) { $label.ForeColor = $muted }
    [IO.File]::WriteAllText($statusPath, '{}')
    $workerArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f (Join-Path $appRoot 'setup.ps1')), '-Device', @('auto', 'cpu', 'cuda')[$deviceCombo.SelectedIndex], '-StatusFile', ('"{0}"' -f $statusPath))
    if ($proxyBox.Text.Trim()) {
        # Validate before putting this value on a child command line.
        $uri = $null
        if (-not [uri]::TryCreate($proxyBox.Text.Trim(), [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https') -or $uri.UserInfo -or $uri.Query -or $proxyBox.Text.Contains('"')) {
            $script:busy = $false
            $heading.Text = '请检查代理地址'
            $message.Text = '填写 http://地址:端口，或留空使用当前网络。'
            $cancel.Text = '关闭'
            $primary.Text = '重试'
            $primary.Enabled = $deviceCombo.Enabled = $proxyBox.Enabled = $true
            return
        }
        $workerArguments += @('-Proxy', ('"{0}"' -f $proxyBox.Text.Trim()))
    }
    try {
        $script:worker = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $workerArguments -WorkingDirectory $appRoot -WindowStyle Hidden -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath -PassThru
        $null = $script:worker.Handle
        Trace-Installer "Worker started: $($script:worker.Id)"
        $timer.Start()
    } catch {
        $script:busy = $false
        $heading.Text = '无法启动安装任务'
        $message.Text = $_.Exception.Message
        $cancel.Text = '关闭'
        $primary.Text = '重试'
        $primary.Enabled = $deviceCombo.Enabled = $proxyBox.Enabled = $true
    }
}
$timer = [Windows.Forms.Timer]::new()
$timer.Interval = 300
$timer.Add_Tick({
    $state = $null
    try { $state = Get-Content -Raw -LiteralPath $statusPath -Encoding UTF8 | ConvertFrom-Json } catch { }
    if ($state -and $state.message) {
        $message.Text = $state.message
        $step = [Math]::Max(0, [Math]::Min(5, [int]$state.step))
        $script:completedSteps = $(if ($state.state -eq 'success') { 5 } else { [Math]::Max(0, $step - 1) })
        $progressFill.Width = [int]($progress.ClientSize.Width * $script:completedSteps / 5)
        $progressFill.BackColor = $(if ($state.state -eq 'success') { $green } else { $accent })
        for ($i = 0; $i -lt $stepNames.Count; $i++) {
            $done = $i -lt $step - 1 -or $state.state -eq 'success'
            $stepLabels[$i].Text = $(if ($done) { '✓  ' } elseif ($i -eq $step - 1) { '●  ' } else { '○  ' }) + $stepNames[$i]
            $stepLabels[$i].ForeColor = $(if ($done) { $green } elseif ($i -eq $step - 1) { $accent } else { $muted })
        }
    }
    $text = ''
    foreach ($logPath in @($outputPath, $errorPath)) {
        $reader = $null
        try {
            $stream = [IO.File]::Open($logPath, 'Open', 'Read', 'ReadWrite')
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
            $text += $reader.ReadToEnd() + "`r`n"
        } catch { }
        finally { if ($reader) { $reader.Dispose() } }
    }
    if ($text.Length -gt 24000) { $text = $text.Substring($text.Length - 24000) }
    if ($details.Text -ne $text) { $details.Text = $text; $details.SelectionStart = $details.TextLength; $details.ScrollToCaret() }
    if ($script:worker.HasExited) {
        $script:worker.WaitForExit()
        Trace-Installer "Worker exited: $($script:worker.ExitCode), status: $($state.state)"
        $timer.Stop()
        $script:busy = $false
        $script:success = $script:worker.ExitCode -eq 0 -and $state.state -eq 'success'
        $primary.Enabled = $deviceCombo.Enabled = $proxyBox.Enabled = $true
        $cancel.Text = '关闭'
        if ($script:success) {
            $script:resultCode = 0
            $heading.Text = '安装完成'
            $heading.ForeColor = $green
            $primary.Text = '打开 App'
            Save-InstallerImage 'installer-complete.png'
            if ($LaunchAfterInstall) { Start-App; $form.Close() }
            elseif ($CloseOnSuccess) { $form.Close() }
        } else {
            $heading.Text = '安装未完成'
            $heading.ForeColor = $red
            $primary.Text = '重试'
            if (-not $state -or $state.state -ne 'error') { $message.Text = '请查看安装详情，检查网络或选择 CPU 模式后重试。' }
        }
    }
})
$primary.Add_Click({
    if ($script:success) { Start-App; $form.Close() } else { Start-Install }
})
$cancel.Add_Click({
    if ($script:busy) {
        $timer.Stop()
        Stop-Worker
        $heading.Text = '安装已取消'
        $message.Text = '已停止本次任务。点击“重试”可继续准备环境。'
        $primary.Text = '重试'
        $primary.Enabled = $deviceCombo.Enabled = $proxyBox.Enabled = $true
        $cancel.Text = '关闭'
    } else { $form.Close() }
})
$form.Add_FormClosing({ param($sender, $eventArgs) Trace-Installer "Closing: $($eventArgs.CloseReason), success: $script:success"; $timer.Stop(); Stop-Worker })
$form.Add_Shown({
    Trace-Installer 'Shown'
    Write-Output 'Installer window shown'
    Save-InstallerImage 'installer-ready.png'
    if ($AutoStart) { Start-Install }
})
try { [Windows.Forms.Application]::Run($form) }
catch {
    $failure = $_.ToString() + "`r`n" + $_.ScriptStackTrace
    [IO.File]::WriteAllText((Join-Path $runtimeRoot 'install-ui-error.log'), $failure)
    if ($CaptureDirectory) { Write-Output $failure }
    else { [Windows.Forms.MessageBox]::Show('安装向导出现错误，请查看 .runtime/install-ui-error.log。', 'Aircraft Icing') | Out-Null }
}
finally {
    Trace-Installer "Run finished: $script:resultCode"
    $timer.Dispose(); $form.Dispose(); $instance.ReleaseMutex(); $instance.Dispose()
}
exit $script:resultCode
