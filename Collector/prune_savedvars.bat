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

set "WTF=%~dp0..\..\..\WTF"
if not exist "%WTF%" (
  echo Could not find WoW WTF folder at %WTF%
  exit /b 1
)

echo Pruning bloated PvPLedger SavedVariables under:
echo   %WTF%
echo.

for /r "%WTF%" %%F in (PvPLedger.lua) do (
  echo Processing %%F
  %PYTHON% prune_savedvars.py "%%F"
)

echo.
echo Done. Start WoW normally - no /reload needed if the game was closed.

endlocal
