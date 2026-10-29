# Optional onedir packaging. This does not bundle the user's model weights.
$ErrorActionPreference = 'Stop'
$appRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $appRoot
$pythonExe = Join-Path $appRoot '.venv\Scripts\python.exe'
& $pythonExe -m pip install 'pyinstaller>=6.16,<7'
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller installation failed.' }
& $pythonExe -m PyInstaller --noconfirm --windowed --onedir --name 'AircraftIcingStudio' --add-data 'qml;qml' --add-data 'assets;assets' --add-data 'config.json;.' --collect-all ultralytics --collect-submodules studio app.py
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
$config = Get-Content -Raw -LiteralPath (Join-Path $appRoot 'config.json') | ConvertFrom-Json
$config.model_path = (Resolve-Path -LiteralPath (Join-Path $appRoot $config.model_path)).Path
$config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $appRoot 'dist\AircraftIcingStudio\config.json') -Encoding UTF8
Write-Host 'Build created in Apps/icing_detector/dist. Packaged GPU/Qt plugins require a separate smoke test.'
