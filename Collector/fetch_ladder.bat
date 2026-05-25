@echo off
setlocal

cd /d "%~dp0"

if exist ".env" (
  echo Using collector\.env
) else (
  echo Missing collector\.env
  echo Copy env.example to .env and add your Battle.net API credentials.
  exit /b 1
)

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

echo Fetching US Blitz ladder snapshot from Battle.net...
%PYTHON% export_ladder.py --fetch-blizzard --region US --output "..\Data\LadderData_US_Blitz.lua"
if %ERRORLEVEL% NEQ 0 exit /b %ERRORLEVEL%

echo.
echo Done. Reload UI in WoW with /reload and run /pvl reload.

endlocal
