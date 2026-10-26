@echo off
setlocal
cd /d "%~dp0"
set "LOG=%~dp0Update.log"
echo Kujiequ 1.8.13 updater > "%LOG%"
echo Start: %DATE% %TIME% >> "%LOG%"
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Apply_Update.ps1" >> "%LOG%" 2>&1
set "RESULT=%ERRORLEVEL%"
if "%RESULT%"=="0" (
  echo Update successful. Log: "%LOG%"
  exit /b 0
)
echo.
echo --------------------------------------------------------
echo Update FAILED. Error code: %RESULT%
echo --------------------------------------------------------
type "%LOG%"
echo.
echo The error log was saved to:
echo "%LOG%"
echo This window will stay OPEN for diagnosis.
echo You can copy the error text or send Update.log.
echo.
cmd.exe /K
