param([string]$Proxy = '', [switch]$ManagedPython)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$env:PYTHONIOENCODING = 'utf-8'
$appRoot = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path $appRoot '.runtime\installer-verification\project\Apps\icing_detector'
New-Item -ItemType Directory -Force -Path $fixture | Out-Null
foreach ($file in @('app.py', 'setup.ps1', 'install.ps1', 'requirements.txt', 'START.cmd', 'INSTALL.cmd')) {
    Copy-Item -LiteralPath (Join-Path $appRoot $file) -Destination (Join-Path $fixture $file) -Force
}
foreach ($folder in @('studio', 'qml', 'assets')) {
    Copy-Item -LiteralPath (Join-Path $appRoot $folder) -Destination $fixture -Recurse -Force
}
$config = Get-Content -Raw -LiteralPath (Join-Path $appRoot 'config.json') -Encoding UTF8 | ConvertFrom-Json
$config.model_path = [IO.Path]::GetFullPath((Join-Path $appRoot $config.model_path))
$config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $fixture 'config.json') -Encoding UTF8
$powershell = Join-Path $PSHOME 'powershell.exe'
$report = @{ checks = @(); freshEnvironment = -not (Test-Path -LiteralPath (Join-Path $fixture '.venv')); managedPython = [bool]$ManagedPython }
function Assert-Check([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:report.checks += $Message
    Write-Output "PASS $Message"
}
try {
    foreach ($name in @('setup.ps1', 'install.ps1')) {
        $tokens = $null; $errors = $null
        [Management.Automation.Language.Parser]::ParseFile((Join-Path $fixture $name), [ref]$tokens, [ref]$errors) | Out-Null
        Assert-Check ($errors.Count -eq 0) "$name parses in Windows PowerShell"
    }
    # Fail before any download when a model is absent; restore the actual config afterward.
    $configPath = Join-Path $fixture 'config.json'
    $originalConfig = [IO.File]::ReadAllText($configPath)
    $config.model_path = Join-Path $fixture 'missing-model.pt'
    $config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
    $statusPath = Join-Path $fixture 'failure-status.json'
    & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'setup.ps1') -StatusFile $statusPath
    $failureCode = $LASTEXITCODE
    [IO.File]::WriteAllText($configPath, $originalConfig, (New-Object Text.UTF8Encoding($true)))
    $failure = Get-Content -Raw -LiteralPath $statusPath -Encoding UTF8 | ConvertFrom-Json
    Assert-Check ($failureCode -eq 1 -and $failure.state -eq 'error' -and $failure.step -eq 1) 'Missing model stops installation before dependency downloads'
    $statusPath = Join-Path $fixture 'installation-status.json'
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $fixture 'setup.ps1'), '-Device', 'cpu', '-StatusFile', $statusPath)
    if ($ManagedPython) { $arguments += '-ManagedPython' }
    if ($Proxy) { $arguments += @('-Proxy', $Proxy) }
    & $powershell @arguments
    $setupCode = $LASTEXITCODE
    $result = Get-Content -Raw -LiteralPath $statusPath -Encoding UTF8 | ConvertFrom-Json
    Assert-Check ($setupCode -eq 0 -and $result.state -eq 'success') 'Independent CPU environment and real model load succeed'
    Push-Location -LiteralPath $fixture
    try {
        $pythonExe = Join-Path $fixture '.venv\Scripts\python.exe'
        & $pythonExe -m studio.environment
        Assert-Check ($LASTEXITCODE -eq 0) 'Installed native dependencies import successfully'
        if ($ManagedPython) {
            $basePath = & $pythonExe -c 'import sys; print(sys.base_prefix)'
            Assert-Check ($basePath.StartsWith((Join-Path $fixture '.runtime\python'), [StringComparison]::OrdinalIgnoreCase)) 'Python is private to the test App; no system Python is used'
        }
        $sharedPaths = Get-ChildItem -LiteralPath (Join-Path $fixture '.venv\Lib\site-packages') -Filter '*shared*.pth'
        Assert-Check (-not $sharedPaths) 'Fresh environment does not reuse external shared CUDA paths'
    } finally { Pop-Location }
    $report.status = 'PASS'
} catch {
    $report.status = 'FAIL'
    $report.error = $_.Exception.Message
    throw
} finally {
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $fixture '..\..\..\installer-report.json') -Encoding UTF8
}
