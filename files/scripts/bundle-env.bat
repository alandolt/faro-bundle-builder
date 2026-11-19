@echo off
rem Sets the bundle's variables for the calling .bat (no setlocal here on purpose).
rem   call scripts\bundle-env.bat <bundle folder>
set "PY=%~1\python\python.exe"
set "CELLPOSE_LOCAL_MODELS_PATH=%~1\models\cellpose"
set "TORCH_HOME=%~1\models\torch"
rem Micro-Manager: an already set MICROMANAGER_PATH wins; then a Micro-Manager*
rem folder inside the bundle; then one next to the bundle.
if defined MICROMANAGER_PATH goto mm_done
for /d %%d in ("%~1\Micro-Manager*") do if not defined MICROMANAGER_PATH set "MICROMANAGER_PATH=%%~fd"
if defined MICROMANAGER_PATH goto mm_done
for /d %%d in ("%~1\..\Micro-Manager*") do if not defined MICROMANAGER_PATH set "MICROMANAGER_PATH=%%~fd"
:mm_done
if defined MICROMANAGER_PATH echo Micro-Manager: %MICROMANAGER_PATH%
