@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\pythonw.exe" (
    echo Please run INSTALL.cmd once, then launch START.cmd again.
    pause
    exit /b 1
)
".venv\Scripts\python.exe" -c "import importlib.util,sys; sys.exit(0 if all(importlib.util.find_spec(m) for m in ['PySide6','ultralytics','torch','PIL']) else 1)"
if errorlevel 1 (
    echo Required dependencies are missing. Please run INSTALL.cmd.
    pause
    exit /b 1
)
start "" ".venv\Scripts\pythonw.exe" -X utf8 "%~dp0app.py" %*
exit /b 0
