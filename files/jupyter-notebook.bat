@echo off
rem Opens Jupyter Notebook in faro-aoki\examples, with the bundle's Python
rem (faro, faro-aoki, cellpose, convpaint, napari) as the kernel.
setlocal
set "B=%~dp0"
if "%B:~-1%"=="\" set "B=%B:~0,-1%"
call "%B%\scripts\bundle-env.bat" "%B%"
"%PY%" -P -m notebook --ServerApp.root_dir="%B%\faro-aoki\examples"
if errorlevel 1 pause
endlocal
