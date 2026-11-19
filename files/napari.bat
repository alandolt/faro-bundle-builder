@echo off
rem Starts plain napari (no Micro-Manager, no microscope) with all plugins of
rem the bundle, e.g. to look at or analyse data.
rem   napari.bat                       empty viewer
rem   napari.bat C:\data\image.ome.tif opens files (or drag files onto this .bat)
setlocal
set "B=%~dp0"
if "%B:~-1%"=="\" set "B=%B:~0,-1%"
call "%B%\scripts\bundle-env.bat" "%B%"
rem python -m instead of napari.exe: the .exe stores an absolute path.
rem -P: never import a package from the current directory instead of the bundle's.
"%PY%" -P -m napari %*
if errorlevel 1 pause
endlocal
