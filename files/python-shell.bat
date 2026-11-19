@echo off
rem Opens a command prompt with the bundle's Python on PATH (python, faro, the
rem lab package, the plugins). Example:  python my_experiment.py
rem Same variables as env.ps1 (PowerShell) and the other .bat files.
rem Run tools as "python -m <module>": the .exe launchers in python\Scripts
rem store the absolute path of the build PC and break when the bundle is moved.
setlocal
set "B=%~dp0"
if "%B:~-1%"=="\" set "B=%B:~0,-1%"
call "%B%\scripts\bundle-env.bat" "%B%"
rem uv (bin\) installs into the bundle's Python when run in env\
set "UV_PROJECT_ENVIRONMENT=%B%\python"
set "UV_PYTHON_PREFERENCE=only-system"
set "UV_LINK_MODE=copy"
set "PATH=%B%\python;%B%\python\Scripts;%B%\bin;%PATH%"
cd /d "%B%"
cmd /k
endlocal
