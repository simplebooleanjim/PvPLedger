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

echo Probing US Arena 3v3 ladder availability on Battle.net...
%PYTHON% export_ladder.py --probe-blizzard --bracket arena3v3 --region US

echo.
echo Probe complete. If matchedCount looks good, run fetch_ladder_3v3.bat next.

endlocal
