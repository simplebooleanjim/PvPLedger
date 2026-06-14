@echo off
setlocal

cd /d "%~dp0\.."

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

echo Building CurseForge/Wago addon packages...
%PYTHON% release\package_addons.py
if %ERRORLEVEL% NEQ 0 exit /b %ERRORLEVEL%

echo.
echo Building Windows installer and sync app...
cd Sync
call build_installer.bat
if %ERRORLEVEL% NEQ 0 exit /b %ERRORLEVEL%

echo.
echo Release artifacts:
echo   Addon zips:  release\dist\*.zip
echo   Installer:   Sync\dist\PvPLedger-Setup.exe
echo   Tray app:    Sync\dist\PvPLedger-Sync.exe
echo.
echo Next steps: see release\RELEASE.md
endlocal
