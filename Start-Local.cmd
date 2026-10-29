@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
    py -3 -c "import sys; sys.exit(sys.version_info < (3,10))" >nul 2>nul
    if not errorlevel 1 (
        py -3 tools\dev_server.py
        goto finished
    )
)
where python >nul 2>nul
if not errorlevel 1 (
    python -c "import sys; sys.exit(sys.version_info < (3,10))" >nul 2>nul
    if not errorlevel 1 (
        python tools\dev_server.py
        goto finished
    )
)
echo Python 3.10 or newer is required.
echo Install Python from https://www.python.org/downloads/windows/
echo Then double-click Start-Local.cmd again.
:finished
echo.
pause
