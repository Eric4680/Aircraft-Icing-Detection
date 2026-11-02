param(
    [ValidateSet('auto', 'cpu', 'cuda')][string]$Device = 'auto',
    [string]$Proxy = '', [string]$StatusFile = '',
    [switch]$ManagedPython, [switch]$FunctionsOnly
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUNBUFFERED = '1'
$env:YOLO_OFFLINE = 'true'
$env:YOLO_AUTOINSTALL = 'false'
$env:PIP_DISABLE_PIP_VERSION_CHECK = '1'
$appRoot = $PSScriptRoot
$runtimeRoot = Join-Path $appRoot '.runtime'
$pythonExe = Join-Path $appRoot '.venv\Scripts\python.exe'
$currentStep = 0

function Report-Step([int]$Step, [string]$Message, [string]$State = 'running') {
    $script:currentStep = $Step
    Write-Output "[$Step/5] $Message"
    if ($StatusFile) {
        $status = @{ step = $Step; message = $Message; state = $State } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($StatusFile, $status, (New-Object Text.UTF8Encoding($false)))
    }
}
function Invoke-Checked {
    param([string]$Executable, [string[]]$Arguments)
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Executable @Arguments 2>&1 | ForEach-Object { Write-Output "$_" }; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $savedPreference }
    if ($code -ne 0) { throw "运行失败（退出码 $code）。请查看详细日志中的下载或依赖错误。" }
}
function Test-Python([string]$Executable, [string[]]$Prefix = @()) {
    if (-not $Executable -or $Executable -like '*\WindowsApps\*') { return $null }
    $probe = "import sys,struct; print(sys.executable) if sys.version_info[:2]==(3,12) and struct.calcsize('P')==8 else sys.exit(1)"
    try {
        $result = & $Executable @Prefix -c $probe 2>$null
        if ($LASTEXITCODE -eq 0 -and $result) { return [string]($result | Select-Object -Last 1) }
    } catch { }
    return $null
}
function Find-Python {
    if (-not $ManagedPython) {
        $existing = Test-Python $pythonExe
        if ($existing) { return $existing }
        $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
        if ($launcher) { $existing = Test-Python $launcher.Source @('-3.12'); if ($existing) { return $existing } }
        $candidate = Get-Command python.exe -ErrorAction SilentlyContinue
        if ($candidate) { $existing = Test-Python $candidate.Source; if ($existing) { return $existing } }
    }
    $managedRoot = Join-Path $runtimeRoot 'python'
    if (Test-Path -LiteralPath $managedRoot) {
        foreach ($candidate in Get-ChildItem -LiteralPath $managedRoot -Filter python.exe -Recurse -File) {
            $existing = Test-Python $candidate.FullName
            if ($existing) { return $existing }
        }
    }
    return $null
}
function Install-LocalPython {
    Report-Step 2 '没有可用的 Python 3.12，正在下载应用专用运行环境…'
    $toolDir = Join-Path $runtimeRoot 'tools\uv-0.13.6'
    $uvExe = Join-Path $toolDir 'uv.exe'
    if (-not (Test-Path -LiteralPath $uvExe)) {
        $archive = Join-Path $runtimeRoot 'uv-0.13.6.zip'
        $request = @{ Uri = 'https://github.com/astral-sh/uv/releases/download/0.13.6/uv-x86_64-pc-windows-msvc.zip'; OutFile = $archive; UseBasicParsing = $true; TimeoutSec = 180 }
        if ($Proxy) { $request.Proxy = $Proxy }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest @request
        $expected = 'a2a8820d5eea32f08ef467ef3b7f66883a9b076d5737a2fc2fbb5f458d1bb50f'
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
            throw '运行环境下载文件校验失败。请重试，或检查网络代理。'
        }
        New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $toolDir -Force
    }
    $env:UV_PYTHON_INSTALL_DIR = Join-Path $runtimeRoot 'python'
    $env:UV_PYTHON_INSTALL_BIN = '0'
    $env:UV_PYTHON_INSTALL_REGISTRY = '0'
    $env:UV_CACHE_DIR = Join-Path $runtimeRoot 'uv-cache'
    Invoke-Checked $uvExe @('python', 'install', '3.12', '--no-bin', '--no-config')
    $resolvedPython = Find-Python
    if (-not $resolvedPython) { throw 'Python 下载结束，但没有找到可运行的 64 位 Python 3.12。' }
    $script:downloadedPython = $resolvedPython
}
function Test-Environment([switch]$RequireCuda) {
    if (-not (Test-Path -LiteralPath $pythonExe)) { return $false }
    $probeArgs = @('-m', 'studio.environment')
    if ($RequireCuda) { $probeArgs += '--cuda' }
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $pythonExe @probeArgs *> $null; return $LASTEXITCODE -eq 0 }
    finally { $ErrorActionPreference = $savedPreference }
}
function Test-Cuda {
    # A missing UI dependency should not replace an otherwise healthy CUDA runtime.
    $probe = "import torch; assert tuple(map(int,torch.__version__.split('.')[:2])) >= (2,14); assert torch.cuda.is_available(); torch.zeros(1,device='cuda:0')"
    try { & $pythonExe -c $probe *> $null; return $LASTEXITCODE -eq 0 }
    catch { return $false }
}
if ($FunctionsOnly) { return }
$installLock = $null
try {
    Set-Location -LiteralPath $appRoot
    if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        throw '当前安装程序支持 Windows x64。请在 64 位 Intel / AMD Windows 电脑上运行。'
    }
    New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
    $installLock = [IO.File]::Open((Join-Path $runtimeRoot 'install.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $env:YOLO_CONFIG_DIR = Join-Path $runtimeRoot 'ultralytics'
    if ($Proxy) {
        $proxyUri = $null
        if (-not [uri]::TryCreate($Proxy, [UriKind]::Absolute, [ref]$proxyUri) -or $proxyUri.Scheme -notin @('http', 'https') -or $proxyUri.UserInfo -or $proxyUri.Query) {
            throw '代理地址格式应为 http://地址:端口，不要填写账号、密码或查询参数。'
        }
        $env:HTTPS_PROXY = $Proxy
        $env:HTTP_PROXY = $Proxy
    }
    Report-Step 1 '正在检查项目文件和模型权重…'
    $config = Get-Content -Raw -LiteralPath (Join-Path $appRoot 'config.json') -Encoding UTF8 | ConvertFrom-Json
    $modelPath = if ([IO.Path]::IsPathRooted($config.model_path)) { $config.model_path } else { [IO.Path]::GetFullPath((Join-Path $appRoot $config.model_path)) }
    if (-not (Test-Path -LiteralPath $modelPath -PathType Leaf)) {
        throw '缺少模型 weights.pt。请完整下载并解压项目，保留 Apps 和 Models 的目录结构。'
    }
    if ((Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $config.expected_sha256) {
        throw '模型校验失败。请重新下载项目中的第一版 weights.pt。'
    }
    Report-Step 2 '正在查找可用的 Python 3.12（64 位）…'
    $basePython = Find-Python
    if (-not $basePython) {
        Install-LocalPython
        $basePython = $downloadedPython
    }
    Write-Output "Python: $basePython"
    Report-Step 3 '正在准备本机运行环境…'
    if (-not (Test-Python $pythonExe)) {
        if (Test-Path -LiteralPath (Join-Path $appRoot '.venv')) {
            throw '现有 .venv 无法运行。请关闭 App，移除本机损坏的 .venv 文件夹，再重新安装。模型与源码无需删除。'
        }
        Invoke-Checked $basePython @('-m', 'venv', (Join-Path $appRoot '.venv'))
    }
    $ready = Test-Environment -RequireCuda:($Device -eq 'cuda')
    Report-Step 4 $(if ($ready) { '已有可用环境，直接复用并继续验证…' } else { '正在安装依赖；首次下载可能需要几分钟，请保持网络连接…' })
    if (-not $ready) {
        Invoke-Checked $pythonExe @('-m', 'pip', 'install', '--upgrade', 'pip', '--timeout', '30', '--retries', '2')
        $cudaReady = Test-Cuda
        $wantCuda = $Device -eq 'cuda' -or ($Device -eq 'auto' -and $null -ne (Get-Command nvidia-smi -ErrorAction SilentlyContinue))
        if ($wantCuda -and -not $cudaReady) {
            try {
                Invoke-Checked $pythonExe @('-m', 'pip', 'install', 'torch==2.14.1', 'torchvision==0.29.1', '--index-url', 'https://download.pytorch.org/whl/cu126', '--timeout', '30', '--retries', '2')
            } catch {
                if ($Device -eq 'cuda') { throw }
                Write-Output 'GPU 运行库下载失败，自动改用 CPU 运行库。需要时可稍后重新安装 GPU 版本。'
                $wantCuda = $false
            }
        }
        if (-not $wantCuda) {
            Invoke-Checked $pythonExe @('-m', 'pip', 'install', 'torch==2.14.1', 'torchvision==0.29.1', '--index-url', 'https://download.pytorch.org/whl/cpu', '--timeout', '30', '--retries', '2')
        }
        Invoke-Checked $pythonExe @('-m', 'pip', 'install', '-r', (Join-Path $appRoot 'requirements.txt'), '--timeout', '30', '--retries', '2')
        Invoke-Checked $pythonExe @('-m', 'studio.environment')
    }
    Report-Step 5 '正在实际加载 Icing 模型，确认安装结果…'
    Invoke-Checked $pythonExe @('-X', 'utf8', (Join-Path $appRoot 'app.py'), '--smoke')
    if ($Device -eq 'cuda' -and -not (Test-Environment -RequireCuda)) {
        throw '依赖已安装，但当前 GPU 无法运行 CUDA。请确认驱动，或在向导中选择 CPU 后重试。'
    }
    Report-Step 5 '安装完成，运行环境和模型加载验证已通过。' 'success'
    exit 0
} catch {
    Report-Step $currentStep "安装未完成：$($_.Exception.Message)" 'error'
    Write-Output $_.ScriptStackTrace
    exit 1
} finally {
    if ($installLock) { $installLock.Dispose() }
}
