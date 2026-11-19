# Paths of the bundle for the current PowerShell window (dot-source it):
#   . <bundle>\env.ps1
#   python my_script.py
# The .bat files set the same variables themselves (scripts\bundle-env.bat).
param([string]$Bundle = $PSScriptRoot)
$env:CELLPOSE_LOCAL_MODELS_PATH = "$Bundle\models\cellpose"
$env:TORCH_HOME                 = "$Bundle\models\torch"
$env:UV_PROJECT_ENVIRONMENT     = "$Bundle\python"   # uv sync in env\ installs into the bundle's Python
$env:UV_PYTHON_PREFERENCE       = "only-system"
$env:UV_LINK_MODE               = "copy"
$env:PATH = "$Bundle\python;$Bundle\python\Scripts;$Bundle\bin;$env:PATH"
if (-not $env:MICROMANAGER_PATH) {
    $mm = @(Get-ChildItem "$Bundle\Micro-Manager*", "$Bundle\..\Micro-Manager*" -Directory -ErrorAction SilentlyContinue)
    if ($mm) { $env:MICROMANAGER_PATH = $mm[0].FullName; "Micro-Manager: $env:MICROMANAGER_PATH" }
}
