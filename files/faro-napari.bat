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
rem Double-clicked (cmd /c ...): hide this console once the napari window is
rem open. A cmd window you typed the command in stays visible.
set "FARO_HIDE_CONSOLE="
set "CL=%CMDCMDLINE:"=%"
if /i not "%CL: /c =%"=="%CL%" set "FARO_HIDE_CONSOLE=1"

if not "%~1"=="" goto run
set "SCOPE=%MICROSCOPE%"
if not "%SCOPE%"=="" goto start
echo Microscopes:
"%PY%" -P -c "from faro.microscope.registry import available_scopes as s; print('  ' + '  '.join(sorted(s())))"
set /p "SCOPE=Which microscope? "
if "%SCOPE%"=="" goto end
:start
"%PY%" -P "%B%\scripts\hide_console.py" faro.napari_launcher %SCOPE%
goto check

:run
rem hide_console.py runs "python -m faro.napari_launcher" (not faro-napari.exe:
rem the .exe stores an absolute path) and hides the console when napari is open.
rem -P: never import a "faro" folder from the current directory instead of the bundle's.
"%PY%" -P "%B%\scripts\hide_console.py" faro.napari_launcher %*

:check
rem On an error, show the console again so the message can be read.
if not errorlevel 1 goto end
"%PY%" -P "%B%\scripts\hide_console.py" --show
pause
:end
endlocal
