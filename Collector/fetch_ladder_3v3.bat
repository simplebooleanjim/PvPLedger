@echo off
setlocal

cd /d "%~dp0"

if exist ".env" (
  echo Using Collector\.env
) else (
  echo Missing Collector\.env
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

echo Fetching US Arena 3v3 ladder snapshot from Battle.net with Seramate enrichment...
%PYTHON% export_ladder.py --fetch-blizzard --bracket arena3v3 --region US --output "..\Data\LadderData_US_Arena3v3.lua"
if %ERRORLEVEL% NEQ 0 exit /b %ERRORLEVEL%

echo.
echo Done. Reload UI in WoW with /reload and run /pvl reload.

endlocal
