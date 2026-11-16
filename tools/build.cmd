@echo off
rem Builds the release zip (data/script/mge.zip) with package.ps1. Double-click it, or run it from any folder;
rem arguments go through to package.ps1, e.g. build.cmd -SkipTests or build.cmd -Out x.zip
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0package.ps1" %*
set code=%errorlevel%
if %code% neq 0 echo. & echo BUILD FAILED (exit code %code%)
rem keep the window open when started from Explorer, so the output can be read
echo %cmdcmdline% | find /i "%~0" >nul && pause
exit /b %code%
