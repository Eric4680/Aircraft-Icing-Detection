@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\pythonw.exe" (
    goto install
)
".venv\Scripts\python.exe" -m studio.environment --quick >nul 2>&1
if errorlevel 1 (
    goto install
)
start "" ".venv\Scripts\pythonw.exe" -X utf8 "%~dp0app.py" %*
exit /b 0
:install
start "" powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0install.ps1" -LaunchAfterInstall %*
exit /b 0
