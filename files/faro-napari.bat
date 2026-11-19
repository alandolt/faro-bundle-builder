@echo off
rem Starts faro-napari (napari + Micro-Manager panel) on a microscope.
rem   faro-napari.bat <microscope>
rem   faro-napari.bat <microscope> --kwarg micromanager_path="D:\Micro-Manager-2.0"
rem Without an argument (double-click) it starts MICROSCOPE below, or, if that
rem is empty, lists the microscopes and asks.
rem
rem Micro-Manager: a "Micro-Manager*" folder inside this folder or next to it is
rem used; otherwise the default install (C:\Program Files\Micro-Manager-2.0).
setlocal

rem ===== Microscope for double-click, e.g. ti2e (empty = ask) =====
set "MICROSCOPE="

set "B=%~dp0"
if "%B:~-1%"=="\" set "B=%B:~0,-1%"
call "%B%\scripts\bundle-env.bat" "%B%"

if not "%~1"=="" goto run
set "SCOPE=%MICROSCOPE%"
if not "%SCOPE%"=="" goto start
echo Microscopes:
"%PY%" -P -c "from faro.microscope.registry import available_scopes as s; print('  ' + '  '.join(sorted(s())))"
set /p "SCOPE=Which microscope? "
if "%SCOPE%"=="" goto end
:start
"%PY%" -P -m faro.napari_launcher %SCOPE%
goto check

:run
rem python -m instead of faro-napari.exe: the .exe stores an absolute path.
rem -P: never import a "faro" folder from the current directory instead of the bundle's.
"%PY%" -P -m faro.napari_launcher %*

:check
if errorlevel 1 pause
:end
endlocal
