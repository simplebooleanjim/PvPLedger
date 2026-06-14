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

set "BUILD_ROOT=%LOCALAPPDATA%\PvPLedger\pyinstaller"
set "BUILD_DIST=%BUILD_ROOT%\dist"
set "BUILD_WORK=%BUILD_ROOT%\work"
if not exist "%BUILD_DIST%" mkdir "%BUILD_DIST%"
if not exist "%BUILD_WORK%" mkdir "%BUILD_WORK%"
if not exist "dist" mkdir "dist"

echo Installing build dependencies...
%PYTHON% -m pip install -r requirements.txt pyinstaller
if %ERRORLEVEL% NEQ 0 exit /b %ERRORLEVEL%

echo Generating brand assets...
%PYTHON% ..\Media\generate_brand_assets.py
if %ERRORLEVEL% NEQ 0 exit /b %ERRORLEVEL%

echo Preparing friend installer addon bundle...
%PYTHON% build\prepare_friend_bundle.py
if %ERRORLEVEL% NEQ 0 exit /b %ERRORLEVEL%

echo Building PvPLedger-Sync.exe...
%PYTHON% -m PyInstaller --noconfirm --distpath "%BUILD_DIST%" --workpath "%BUILD_WORK%" build\pvpledger_sync.spec
if %ERRORLEVEL% NEQ 0 exit /b %ERRORLEVEL%

copy /Y "%BUILD_DIST%\PvPLedger-Sync.exe" "dist\PvPLedger-Sync.exe" >nul
set "PVL_SYNC_EXE=%BUILD_DIST%\PvPLedger-Sync.exe"

echo Building PvPLedger-Setup.exe...
%PYTHON% -m PyInstaller --noconfirm --distpath "%BUILD_DIST%" --workpath "%BUILD_WORK%" build\pvpledger_setup.spec
if %ERRORLEVEL% NEQ 0 exit /b %ERRORLEVEL%

copy /Y "%BUILD_DIST%\PvPLedger-Setup.exe" "dist\PvPLedger-Setup.exe" >nul

echo.
echo Done.
echo   Tray app:   dist\PvPLedger-Sync.exe
echo   Installer:  dist\PvPLedger-Setup.exe
echo.
echo Note: custom exe icons may not appear on this PC due to a PyInstaller
echo       limitation. The apps will still run correctly.
echo.
endlocal
