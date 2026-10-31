$ErrorActionPreference = 'Stop'
$appRoot = Split-Path $PSScriptRoot -Parent
$baker = Join-Path $appRoot '.venv\Scripts\pyside6-qsb.exe'
foreach ($shader in Get-ChildItem -LiteralPath (Join-Path $appRoot 'qml\shaders') -Filter '*.frag') {
    & $baker --qt6 -o ($shader.FullName + '.qsb') $shader.FullName
    if ($LASTEXITCODE -ne 0) { throw "Shader compilation failed: $($shader.Name)" }
}
