param([ValidateSet('auto', 'cpu', 'cuda')][string]$Device = 'auto')
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$pythonExe = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
function Checked-Python {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    & $pythonExe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Python command failed with exit code $LASTEXITCODE" }
}
if (-not (Test-Path -LiteralPath $pythonExe)) {
    if (Get-Command py -ErrorAction SilentlyContinue) { & py -3.12 -m venv (Join-Path $PSScriptRoot '.venv') }
    else { & python -m venv (Join-Path $PSScriptRoot '.venv') }
    if ($LASTEXITCODE -ne 0) { throw 'Install Python 3.12 x64 first.' }
}
Checked-Python @('-m', 'pip', 'install', '--upgrade', 'pip')
$wantCuda = $Device -eq 'cuda' -or ($Device -eq 'auto' -and $null -ne (Get-Command nvidia-smi -ErrorAction SilentlyContinue))
if ($wantCuda) {
    & $pythonExe -c 'import sys,torch; sys.exit(0 if torch.cuda.is_available() else 1)' 2>$null
    $cudaReady = $LASTEXITCODE -eq 0
    if ($cudaReady) {
        Write-Host 'An available CUDA runtime is already configured; reusing it.'
    } else {
    Write-Host 'Installing official CUDA 12.8 PyTorch for NVIDIA GPU...'
    & $pythonExe -m pip install torch==2.9.1 torchvision==0.24.1 --index-url https://download.pytorch.org/whl/cu128
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Trying the official download domain linked from the PyTorch index...'
        & $pythonExe -m pip install torch==2.9.1 torchvision==0.24.1 --index-url https://download-r2.pytorch.org/whl/cu128
        if ($LASTEXITCODE -ne 0) {
            if ($Device -eq 'cuda') { throw 'CUDA download failed. Retry later or use INSTALL.cmd -Device cpu.' }
            Write-Warning 'CUDA download failed. Installing a CPU runtime.'
            Checked-Python @('-m', 'pip', 'install', 'torch==2.9.1', 'torchvision==0.24.1')
        }
    }
    }
} elseif ($Device -eq 'cpu') {
    Checked-Python @('-m', 'pip', 'install', 'torch==2.9.1', 'torchvision==0.24.1')
}
Checked-Python @('-m', 'pip', 'install', '-r', (Join-Path $PSScriptRoot 'requirements.txt'))
Checked-Python @('-X', 'utf8', (Join-Path $PSScriptRoot 'app.py'), '--smoke')
Write-Host 'Installation and real-weight loading completed.'
