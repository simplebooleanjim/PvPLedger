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

echo Probing US Rated Battlegrounds ladder index on Battle.net...
%PYTHON% export_ladder.py --probe-blizzard --bracket rbg --region US
if %ERRORLEVEL% NEQ 0 exit /b %ERRORLEVEL%

echo.
echo Probe complete. If matchedCount looks good, run fetch_ladder_rbg.bat next.

endlocal
