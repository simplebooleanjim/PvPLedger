@echo off
setlocal

cd /d "%~dp0"

where python >nul 2>&1
if %ERRORLEVEL%==0 (
  set PYTHON=python
) else (
  where py >nul 2>&1
  if %ERRORLEVEL%==0 (
    set PYTHON=py -3
  ) else (
    echo Python was not found. Install Python 3 and try again.
    exit /b 1
  )
)

%PYTHON% -m pip show pystray >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
  echo Installing tray dependencies...
  %PYTHON% -m pip install -r requirements.txt
  if %ERRORLEVEL% NEQ 0 exit /b %ERRORLEVEL%
)

where pythonw >nul 2>&1
if %ERRORLEVEL%==0 (
  start "" pythonw -m pvpledger_sync tray
) else (
  start "" %PYTHON% -m pvpledger_sync tray
)

echo PvPLedger Sync tray app started.
endlocal
