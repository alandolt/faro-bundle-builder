@echo off
rem Double-click to build a portable faro bundle (runs build-bundle.ps1).
rem Windows blocks .ps1 scripts by default; -ExecutionPolicy Bypass allows this
rem one script for this run only and changes no system setting.
rem Parameters are passed on, e.g.  build-bundle.bat -Lab aoki -Yes
set "FARO_BUILD_BAT=1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-bundle.ps1" %*
echo.
pause
