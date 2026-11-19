# Build a portable, offline faro bundle on a PC WITH internet (Windows x64).
#
#   double-click build-bundle.bat
#   or: powershell -ExecutionPolicy Bypass -File build-bundle.ps1
# (Windows blocks .ps1 files by default; the .bat starts this one with Bypass.)
#
# Asks for the lab package (faro-aoki, faro-pertzlab or another git repository),
# the folder, the napari plugins and a few options, then builds:
#   python\            standalone Python 3.12 with every package installed in it
#                      (no venv: nothing stores the folder's path, so the bundle
#                      runs from any folder or drive without changes)
#   faro\  <lab>\      git clones, installed editable (code changes apply directly)
#   models\            cellpose-SAM, convpaint weights, GUI icon sets (offline)
#   faro-napari.bat    start napari + Micro-Manager on a microscope
#   napari.bat         plain napari with the plugins (no microscope)
#   python-shell.bat   command prompt with the bundle's Python
#   builder\           this script, to rebuild or update the bundle later
#
# Run it again on an existing bundle folder to update it: the clones get a
# git pull (a clone with local changes or local commits is left as it is), all
# packages are resolved again to their newest versions (git branches such as the
# pertzlab pymmcore-widgets build too), and the last choices (bundle-config.json)
# are the defaults. -NoPull keeps the clones, -KeepLock keeps the package
# versions of the last build. Without questions: add -Yes (and the parameters
# below as needed).
#
# Needs: git and uv on PATH (uv: https://docs.astral.sh/uv/).
param(
    [string]$Bundle = "",                 # bundle folder (default: .\faro-<lab>-offline)
    [string]$Lab = "",                    # aoki | pertzlab | <git URL of another lab package>
    [string]$LabBranch = "main",
    [string[]]$Plugins = $null,           # e.g. cellpose,convpaint,skimage,timestamper,jupyter
    [string[]]$ExtraPackages = $null,     # more PyPI packages, e.g. napari-animation
    [ValidateSet("", "newest", "api74", "api75")][string]$MMApi = "",
    [ValidateSet("", "cpu", "cu130")][string]$Torch = "",
    [string]$Microscope = $null,          # started by a double-click on faro-napari.bat ("" = ask)
    [string]$FaroUrl = "https://github.com/alandolt/faro.git",
    [string]$FaroBranch = "main",
    [string]$ModelsFrom = "",             # copy models from an existing bundle's models\ folder
    # Self-extracting <bundle>.exe next to the bundle folder (needs 7-Zip on this PC):
    # fast (fastest compression, default) | normal (a bit smaller, much slower to build) | none
    # (no store-only: Windows does not start an .exe of 4 GB or more)
    [ValidateSet("", "fast", "normal", "none")][string]$Package = "",
    # What git clones of faro and the lab package: main (only the main branch,
    # default) | shallow (only the latest commit of main) | all (every branch)
    [ValidateSet("", "main", "shallow", "all")][string]$Clone = "",
    [switch]$NoPull,                      # existing clones: no git pull
    [switch]$KeepLock,                    # keep the package versions of env\uv.lock (no re-resolve)
    [switch]$Yes                          # no questions: defaults + parameters
)
# On an error: show it, and keep a window that "Run with PowerShell" opened
# from closing (build-bundle.bat pauses by itself and sets FARO_BUILD_BAT).
trap {
    Write-Host "`nERROR: $_" -ForegroundColor Red
    if (-not $env:FARO_BUILD_BAT -and -not $Yes) { Read-Host "Press Enter to close" | Out-Null }
    exit 1
}
# No "Stop": PowerShell 5.1 would treat uv's progress output (stderr) as an error.
function Check([string]$what) { if ($LASTEXITCODE) { throw "$what failed (exit code $LASTEXITCODE)" } }
$NoBom = New-Object Text.UTF8Encoding $false
$PythonVersion = "3.12"

# ---------------------------------------------------------------- catalogs
$Labs = [ordered]@{
    aoki     = @{ Url = "https://github.com/alandolt/faro-aoki.git";    Label = "faro-aoki      Aoki lab (IX83 unit 2, IX83 CSU, Ti2-E)" }
    pertzlab = @{ Url = "https://github.com/pertzlab/faro-pertzlab.git"; Label = "faro-pertzlab  Pertz lab (Moench, Niesen, Jungfrau)" }
}
# Key, label, PyPI packages, faro extras, needs torch.
# cellpose / convpaint are listed directly, not as faro[cellpose] / faro[convpaint]:
# those extras bring faro's CUDA torch index, which clashes with the one chosen here.
$Catalog = @(
    @{ Key = "cellpose";         Label = "cellpose-SAM       segmentation (napari-cellposesam, cellpose 4, model cpsam_v2)"; Pkgs = @("napari-cellposesam", "cellpose>=4.1.1", "opencv-python"); Extras = @(); Torch = $true }
    @{ Key = "convpaint";        Label = "convpaint          pixel classifier (napari-convpaint, default feature model)";    Pkgs = @("napari-convpaint", "scipy"); Extras = @(); Torch = $true }
    @{ Key = "skimage";          Label = "skimage            scikit-image filters in napari (napari-skimage)";               Pkgs = @("napari-skimage");     Extras = @();            Torch = $false }
    @{ Key = "napari-tiff";      Label = "napari-tiff        TIFF / OME-TIFF reader, lists of files + multi-position (alandolt fork, git)"; Pkgs = @("napari-tiff @ git+https://github.com/alandolt/napari-tiff.git@main"); Extras = @(); Torch = $false }
    @{ Key = "timestamper";      Label = "timestamper        time stamps / scale bars on videos (napari-timestamper)";      Pkgs = @("napari-timestamper"); Extras = @();            Torch = $false }
    @{ Key = "jupyter";          Label = "Jupyter Notebook   notebooks with the bundle's Python (jupyter-notebook.bat)";    Pkgs = @("notebook");           Extras = @();            Torch = $false }
    @{ Key = "ipykernel";        Label = "ipykernel          notebooks in VS Code etc. with the bundle's Python as kernel"; Pkgs = @("ipykernel");          Extras = @();            Torch = $false }
    @{ Key = "motile";           Label = "motile             tracking backend for faro (faro[motile])";                     Pkgs = @();                     Extras = @("motile");    Torch = $false }
    @{ Key = "pertzlab-widgets"; Label = "pertzlab widgets   pymmcore-widgets with stage map / continuous focus (git build)"; Pkgs = @();                 Extras = @("pertzlab-widgets"); Torch = $false }
)
$DefaultPlugins = @{
    aoki     = @("cellpose", "convpaint", "skimage", "napari-tiff", "timestamper", "jupyter", "ipykernel", "pertzlab-widgets")
    pertzlab = @("cellpose", "convpaint", "skimage", "napari-tiff", "timestamper", "jupyter", "ipykernel", "pertzlab-widgets")
    other    = @("cellpose", "convpaint", "skimage", "napari-tiff", "timestamper", "jupyter", "ipykernel")
}

# ---------------------------------------------------------------- prompts
function Ask([string]$prompt, [string]$default) {
    if ($Yes) { return $default }
    $a = Read-Host "$prompt [$default]"
    if ([string]::IsNullOrWhiteSpace($a)) { return $default } else { return $a.Trim() }
}
function AskChoice([string]$title, [string[]]$keys, [string[]]$labels, [string]$default) {
    if ($Yes) { return $default }
    Write-Host "`n$title"
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $mark = if ($keys[$i] -eq $default) { "*" } else { " " }
        Write-Host ("  {0}{1}) {2}" -f $mark, ($i + 1), $labels[$i])
    }
    while ($true) {
        $a = Read-Host "Number (Enter = *)"
        if ([string]::IsNullOrWhiteSpace($a)) { return $default }
        $n = 0
        if ([int]::TryParse($a, [ref]$n) -and $n -ge 1 -and $n -le $keys.Count) { return $keys[$n - 1] }
    }
}
function AskToggles([string]$title, $items, [string[]]$selected) {
    $sel = New-Object System.Collections.Generic.List[string]
    foreach ($s in $selected) { if ($s) { $sel.Add($s) } }
    if ($Yes) { return , $sel.ToArray() }
    while ($true) {
        Write-Host "`n$title"
        for ($i = 0; $i -lt $items.Count; $i++) {
            $mark = if ($sel.Contains($items[$i].Key)) { "x" } else { " " }
            Write-Host ("  [{0}] {1}) {2}" -f $mark, ($i + 1), $items[$i].Label)
        }
        $a = Read-Host "Numbers to switch on/off (e.g. 2 6), Enter = done"
        if ([string]::IsNullOrWhiteSpace($a)) { return , $sel.ToArray() }
        foreach ($t in ($a -split '[\s,;]+')) {
            $n = 0
            if ([int]::TryParse($t, [ref]$n) -and $n -ge 1 -and $n -le $items.Count) {
                $k = $items[$n - 1].Key
                if ($sel.Contains($k)) { [void]$sel.Remove($k) } else { $sel.Add($k) }
            }
        }
    }
}

# ---------------------------------------------------------------- 0. tools
$uvCmd = Get-Command uv -ErrorAction SilentlyContinue
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $uvCmd) { throw "uv not found on PATH (https://docs.astral.sh/uv/getting-started/installation/)" }
if (-not $gitCmd) { throw "git not found on PATH" }
$uv = $uvCmd.Source
# 7-Zip (only for the self-extracting .exe)
$sevenZip = @((Get-Command 7z -ErrorAction SilentlyContinue).Source,
              "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") |
    Where-Object { $_ -and (Test-Path $_) -and (Test-Path (Join-Path (Split-Path $_) "7z.sfx")) } |
    Select-Object -First 1

# ---------------------------------------------------------------- 1. lab + folder
# Started from a bundle's builder\ folder: update that bundle, with its lab.
$parent = Split-Path $PSScriptRoot -Parent
if (-not $Bundle -and (Split-Path $PSScriptRoot -Leaf) -eq "builder" -and (Test-Path "$parent\bundle-config.json")) {
    $Bundle = $parent
    $prev = Get-Content "$parent\bundle-config.json" -Raw | ConvertFrom-Json
    if (-not $Lab) { $Lab = $prev.LabUrl; $LabBranch = $prev.LabBranch }
    Write-Host "Updating the bundle $Bundle ($($prev.LabUrl))"
}
if (-not $Lab) {
    $Lab = AskChoice "Lab package (the microscopes):" (@($Labs.Keys) + "other") `
        (@($Labs.Values | ForEach-Object { $_.Label }) + "another lab package (git URL)") "aoki"
}
foreach ($k in $Labs.Keys) { if ($Lab -eq $Labs[$k].Url) { $Lab = $k } }   # known URL -> its key
if ($Labs.Contains($Lab)) { $LabKey = $Lab; $LabUrl = $Labs[$Lab].Url }
else {
    $LabKey = "other"
    $LabUrl = if ($Lab -match '://|^git@') { $Lab } else { Ask "Git URL of the lab package" "" }
    if (-not $LabUrl) { throw "No git URL given" }
    if ($Lab -eq "other") { $LabBranch = Ask "Branch" $LabBranch }
}
$LabDir = ($LabUrl.TrimEnd('/') -split '[/:]')[-1] -replace '\.git$', ''

if (-not $Bundle) { $Bundle = Ask "`nBundle folder" (Join-Path (Get-Location) "$LabDir-offline") }
$Bundle = [IO.Path]::GetFullPath($Bundle).TrimEnd('\')
New-Item -ItemType Directory -Force $Bundle | Out-Null

# Last choices of this bundle = defaults
$cfgFile = "$Bundle\bundle-config.json"
$last = $null
if (Test-Path $cfgFile) {
    $last = Get-Content $cfgFile -Raw | ConvertFrom-Json
    Write-Host "Existing bundle: its last choices are the defaults."
}

# ---------------------------------------------------------------- 2. clones (needed to list the microscopes)
$needClone = -not ((Test-Path "$Bundle\faro\.git") -and (Test-Path "$Bundle\$LabDir\.git"))
if ($needClone -and -not $Clone) {
    $def = if ($last -and $last.Clone) { $last.Clone } else { "main" }
    $Clone = AskChoice "Git clones of faro and $LabDir :" @("main", "shallow", "all") `
        @("only the main branch     (full history of main; git pull/push work)",
          "only the latest commit   (smallest, fastest; git pull works, no history)",
          "all branches             (everything on GitHub; largest, slowest)") $def
}
if (-not $Clone) { $Clone = "main" }
# @(...) keeps a list: a single "--single-branch" would become a string, and
# @string passes it to git character by character.
$cloneArgs = @(switch ($Clone) {
    "main"    { "--single-branch" }
    "shallow" { "--single-branch", "--depth", "1" }
})
# Update an existing clone. Never overwrites work: a clone with local changes
# or with commits that are not on GitHub is left as it is (with a warning).
function Update-Clone([string]$name, [string]$dir) {
    $before = (git -C $dir rev-parse --short HEAD)
    if (git -C $dir status --porcelain --untracked-files=no) {
        Write-Host "$name : local changes, not updated (still $before)" -ForegroundColor Yellow
        return
    }
    $branch = (git -C $dir rev-parse --abbrev-ref HEAD)
    if ($branch -eq "HEAD") {
        Write-Host "$name : no branch checked out (detached), not updated (still $before)" -ForegroundColor Yellow
        return
    }
    if ((git -C $dir rev-parse --is-shallow-repository) -eq "true") {
        # Shallow clone: fetch only the newest commit and move to it
        git -C $dir fetch --depth 1 origin $branch
        if ($LASTEXITCODE) { Write-Host "$name : git fetch failed, not updated (still $before)" -ForegroundColor Yellow; return }
        git -C $dir reset --hard FETCH_HEAD | Out-Null
    } else {
        git -C $dir pull --ff-only
        if ($LASTEXITCODE) {
            Write-Host "$name : git pull --ff-only failed (local commits or no network), not updated (still $before)" -ForegroundColor Yellow
            return
        }
    }
    $after = (git -C $dir rev-parse --short HEAD)
    if ($after -eq $before) { Write-Host "$name : up to date ($branch $after)" }
    else { Write-Host "$name : updated $before -> $after ($branch)" }
}
foreach ($r in @(@("faro", $FaroUrl, $FaroBranch), @($LabDir, $LabUrl, $LabBranch))) {
    $dir = "$Bundle\$($r[0])"
    if (Test-Path "$dir\.git") {
        if ($NoPull) { Write-Host "$($r[0]): already cloned, left as it is (-NoPull)" }
        else { Update-Clone $r[0] $dir }
    }
    elseif (Test-Path $dir) { throw "$dir exists but is not a git clone" }
    else { git clone --branch $r[2] @cloneArgs $r[1] $dir; Check "git clone $($r[0])" }
}
$labToml = Get-Content "$Bundle\$LabDir\pyproject.toml"
$LabPkg = ($labToml | Select-String -Pattern '^\s*name\s*=\s*"([^"]+)"' | Select-Object -First 1).Matches[0].Groups[1].Value
$scopes = @(); $inEp = $false
foreach ($line in $labToml) {
    if ($line -match '^\s*\[') { $inEp = $line -match 'entry-points\."faro\.microscopes"' ; continue }
    if ($inEp -and $line -match '^\s*([A-Za-z0-9_.-]+)\s*=') { $scopes += $Matches[1] }
}
Write-Host "Lab package: $LabPkg ($LabDir), microscopes: $($scopes -join ', ')"

# ---------------------------------------------------------------- 3. options
if ($null -eq $Plugins) {
    $def = if ($last) {
        # The last choices; options added to the builder since then get their
        # default (bundle-config.json from before "Offered" knew all but napari-tiff)
        $offered = if ($last.Offered) { @($last.Offered) } else { @($Catalog.Key | Where-Object { $_ -ne "napari-tiff" }) }
        @($last.Plugins) + @($DefaultPlugins[$LabKey] | Where-Object { $offered -notcontains $_ })
    } else { $DefaultPlugins[$LabKey] }
    $Plugins = AskToggles "Plugins and extras in the bundle:" $Catalog $def
}
$Plugins = @($Plugins | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
foreach ($p in $Plugins) { if (-not ($Catalog | Where-Object { $_.Key -eq $p })) { throw "Unknown plugin '$p'" } }

if ($null -eq $ExtraPackages) {
    $def = if ($last) { (@($last.ExtraPackages) -join ' ') } else { "" }
    $ExtraPackages = @((Ask "`nMore PyPI packages (space separated, Enter = none)" $def) -split '\s+' | Where-Object { $_ })
}

if (-not $MMApi) {
    $def = if ($last) { $last.MMApi } else { "newest" }
    $MMApi = AskChoice "pymmcore build (must match the device interface of the Micro-Manager on the microscope PC, Help > About):" `
        @("newest", "api74", "api75") @("newest from PyPI", "device interface 74", "device interface 75") $def
}

$needTorch = [bool]($Catalog | Where-Object { $Plugins -contains $_.Key -and $_.Torch })
if ($needTorch -and -not $Torch) {
    $def = if ($last -and $last.Torch) { $last.Torch } else { "cpu" }
    $Torch = AskChoice "torch (for cellpose / convpaint):" @("cpu", "cu130") `
        @("CPU only (any PC, ~1 GB)", "NVIDIA GPU, CUDA 13.0 (driver >= 580; ~4 GB)") $def
}

if (-not $PSBoundParameters.ContainsKey("Microscope")) {   # [string] turns $null into ""
    $def = if ($last) { $last.Microscope } else { "" }
    if (-not $Yes) { Write-Host "`nMicroscopes: $($scopes -join '  ')" }
    $Microscope = Ask "Microscope started by a double-click on faro-napari.bat (- = ask each time)" $(if ($def) { $def } else { "-" })
    if ($Microscope -eq "-") { $Microscope = "" }
}

if (-not $Package) {
    $def = if ($last -and $last.Package -in @("fast", "normal", "none")) { $last.Package } else { "fast" }
    $Package = AskChoice "Self-extracting .exe of the bundle (one file to copy to the microscope PC):" `
        @("fast", "normal", "none") `
        @("fastest compression (about 1 min to pack, ~2.3 GB for a 4.2 GB bundle)",
          "normal compression  (about 5 min to pack, ~7% smaller)",
          "no .exe             (just the folder)") $def
}
if ($Package -ne "none" -and -not $sevenZip) {
    throw "The self-extracting .exe needs 7-Zip (https://www.7-zip.org) on this PC, or choose 'no .exe' (-Package none)"
}

# ---------------------------------------------------------------- summary
$extras = @(@($Catalog | Where-Object { $Plugins -contains $_.Key } | ForEach-Object { $_.Extras }) | Where-Object { $_ })
if ($MMApi -ne "newest") { $extras += $MMApi }
$extras = @($extras | Select-Object -Unique)
$pkgs = @(@($Catalog | Where-Object { $Plugins -contains $_.Key } | ForEach-Object { $_.Pkgs }) + @($ExtraPackages) | Where-Object { $_ })
$faroReq = if ($extras) { "faro[$($extras -join ',')]" } else { "faro" }

Write-Host ""
Write-Host "Bundle      : $Bundle"
Write-Host "faro        : $FaroUrl ($FaroBranch)"
Write-Host "Lab package : $LabPkg  $LabUrl ($LabBranch)"
Write-Host "Git clones  : $(if ($needClone) { $Clone } elseif ($NoPull) { 'already there, kept (-NoPull)' } else { 'already there, updated (git pull)' })"
Write-Host "Packages    : $(if ($KeepLock -and (Test-Path "$Bundle\env\uv.lock")) { 'versions of the last build (-KeepLock)' } else { 'newest versions (resolved again)' })"
Write-Host "Plugins     : $($Plugins -join ', ')"
Write-Host "More pkgs   : $(if ($ExtraPackages) { $ExtraPackages -join ', ' } else { '-' })"
Write-Host "pymmcore    : $MMApi"
Write-Host "torch       : $(if ($needTorch) { $Torch } else { '-' })"
Write-Host "Double-click: $(if ($Microscope) { $Microscope } else { 'ask' })"
Write-Host "Package     : $(if ($Package -eq 'none') { 'no .exe' } else { "$Bundle.exe ($Package)" })"
if (-not $Yes) {
    $a = Read-Host "`nBuild? [Y/n]"
    if ($a -and $a -notmatch '^[yYjJ]') { Write-Host "Cancelled."; return }
}
[IO.File]::WriteAllText($cfgFile, (@{
    Lab = $Lab; LabUrl = $LabUrl; LabBranch = $LabBranch; Plugins = $Plugins; ExtraPackages = $ExtraPackages
    MMApi = $MMApi; Torch = $Torch; Microscope = $Microscope; FaroUrl = $FaroUrl; FaroBranch = $FaroBranch
    Package = $Package; Clone = $Clone; Offered = @($Catalog.Key)
} | ConvertTo-Json), $NoBom)

# ---------------------------------------------------------------- 4. uv + Python
New-Item -ItemType Directory -Force "$Bundle\bin", "$Bundle\env" | Out-Null
foreach ($exe in "uv", "uvx") {
    $c = Get-Command $exe -ErrorAction SilentlyContinue
    if ($c -and ($c.Source -ne "$Bundle\bin\$exe.exe")) { Copy-Item $c.Source "$Bundle\bin\" -Force }
}
$Py = "$Bundle\python\python.exe"
if (-not (Test-Path $Py)) {
    # Download into a temporary folder, then copy only the real interpreter folder
    # (uv's "cpython-3.12-..." link next to it stores an absolute path).
    $tmp = "$Bundle\.python-download"
    & $uv python install $PythonVersion --install-dir $tmp --no-bin --no-registry; Check "uv python install"
    $real = Get-ChildItem $tmp -Directory | Where-Object {
        -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and (Test-Path "$($_.FullName)\python.exe") } |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $real) { throw "No Python found in $tmp" }
    robocopy $real.FullName "$Bundle\python" /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "copying Python failed" }
    cmd /c rmdir /s /q "`"$tmp`""      # rmdir does not follow the link
    # Packages go straight into this Python; it is the bundle's own, not a system one.
    Remove-Item "$Bundle\python\Lib\EXTERNALLY-MANAGED" -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- 5. packages
function TomlList($items) { ($items | ForEach-Object { "    `"$_`"," }) -join "`n" }
$deps = @($LabPkg, $faroReq) + $pkgs
if ($needTorch) { $deps += "torch", "torchvision" }
$torchIndex = if ($Torch -eq "cu130") { "https://download.pytorch.org/whl/cu130" } else { "https://download.pytorch.org/whl/cpu" }
$torchToml = if ($needTorch) { @"

[[tool.uv.index]]
name = "pytorch"
url = "$torchIndex"
explicit = true
"@ } else { "" }
$torchSrc = if ($needTorch) { "torch       = { index = `"pytorch`" }`ntorchvision = { index = `"pytorch`" }" } else { "" }
$pyproject = @"
# Written by build-bundle.ps1 (edit the choices there, or bundle-config.json + rebuild).
[project]
name = "faro-bundle"
version = "0.0.0"
requires-python = ">=$PythonVersion,<3.13"
dependencies = [
$(TomlList $deps)
]

[tool.uv]
package = false
environments = ["sys_platform == 'win32' and platform_machine == 'AMD64'"]
# The lab package pins faro from git; this uses the editable clone in ..\faro.
# With the extras: a bare "faro" here would drop them.
override-dependencies = ["$faroReq"]
$torchToml
[tool.uv.sources]
faro = { path = "../faro", editable = true }
$LabPkg = { path = "../$LabDir", editable = true }
$torchSrc
"@
[IO.File]::WriteAllText("$Bundle\env\pyproject.toml", $pyproject, $NoBom)

# uv installs into the bundle's Python itself (no .venv), copies instead of hardlinks.
$env:UV_PROJECT_ENVIRONMENT = "$Bundle\python"
$env:UV_PYTHON_PREFERENCE = "only-system"
$env:UV_LINK_MODE = "copy"
Push-Location "$Bundle\env"
try {
    # --upgrade: resolve every package again, so a git branch (e.g. the pertzlab
    # pymmcore-widgets build) is taken at its newest commit, not the one an
    # existing uv.lock pinned. -KeepLock keeps the versions of the last build.
    if ($KeepLock) { & $uv lock } else { & $uv lock --upgrade }
    Check "uv lock"
    & $uv sync --frozen; Check "uv sync"
} finally { Pop-Location }

# What went into this bundle (shown at the end and written to README.txt)
function Commit-Of([string]$dir) { (git -C $dir log -1 --format="%h %cs %s") }
$faroCommit = Commit-Of "$Bundle\faro"
$labCommit = Commit-Of "$Bundle\$LabDir"
$lockText = Get-Content "$Bundle\env\uv.lock" -Raw
$widgets = if ($lockText -match 'pymmcore-widgets\.git\?branch=([^#"]+)#([0-9a-f]{40})') {
    "git $($Matches[1]) $($Matches[2].Substring(0, 7))"
} elseif ($lockText -match '(?m)^name = "pymmcore-widgets"\r?\nversion = "([^"]+)"') {
    "PyPI $($Matches[1])"
} else { "?" }

# ---------------------------------------------------------------- 6. launchers + helper scripts
$src = "$PSScriptRoot\files"
robocopy $src $Bundle /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "copying files failed" }
if ($PSScriptRoot -ne "$Bundle\builder") {
    New-Item -ItemType Directory -Force "$Bundle\builder" | Out-Null
    foreach ($f in "build-bundle.ps1", "build-bundle.bat") {
        if (Test-Path "$PSScriptRoot\$f") { Copy-Item "$PSScriptRoot\$f" "$Bundle\builder\" -Force }
    }
    robocopy $src "$Bundle\builder\files" /E /NFL /NDL /NJH /NJS /NP | Out-Null
}
# Double-click microscope
$bat = Get-Content "$Bundle\faro-napari.bat"
$bat = $bat -replace '^set "MICROSCOPE=.*"$', "set `"MICROSCOPE=$Microscope`""
[IO.File]::WriteAllLines("$Bundle\faro-napari.bat", [string[]]$bat, (New-Object Text.ASCIIEncoding))
# Jupyter: start in the lab package's examples (else faro's)
if ($Plugins -contains "jupyter") {
    $nb = if (Test-Path "$Bundle\$LabDir\examples") { "$LabDir\examples" } elseif (Test-Path "$Bundle\faro\examples") { "faro\examples" } else { "" }
    $j = (Get-Content "$Bundle\jupyter-notebook.bat") -replace '%B%\\faro-aoki\\examples', $(if ($nb) { "%B%\$nb" } else { "%B%" })
    [IO.File]::WriteAllLines("$Bundle\jupyter-notebook.bat", [string[]]$j, (New-Object Text.ASCIIEncoding))
} else { Remove-Item "$Bundle\jupyter-notebook.bat" -ErrorAction SilentlyContinue }

# Editable installs: relative paths in site-packages\*.pth (portable folder)
& $Py "$Bundle\scripts\relative_pth.py"; Check "relative_pth"
# The bundle's Python sets the models / Micro-Manager variables itself at every
# start, also when VS Code or Jupyter start it (not only via the .bat files)
& $Py "$Bundle\scripts\install_bundle_env.py"; Check "install_bundle_env"
# VS Code: python\python.exe as interpreter and notebook kernel (relative path;
# existing settings are kept, .vscode/ is excluded locally in the clones)
$vsFolders = @(".", "faro", $LabDir, "faro\examples", "$LabDir\examples") | Where-Object { Test-Path "$Bundle\$_" }
& $Py "$Bundle\scripts\vscode_settings.py" @vsFolders; Check "vscode_settings"

# ---------------------------------------------------------------- 7. offline icons + models
$env:CELLPOSE_LOCAL_MODELS_PATH = "$Bundle\models\cellpose"
$env:TORCH_HOME = "$Bundle\models\torch"
New-Item -ItemType Directory -Force "$Bundle\models\cellpose", "$Bundle\models\torch", "$Bundle\models\pyconify" | Out-Null
& $Py "$Bundle\scripts\install_offline_icons.py"; Check "install_offline_icons"
if ($ModelsFrom) {
    # cellpose\cpsam_v2 is one file; the others are folders
    if ((Test-Path "$ModelsFrom\cellpose\cpsam_v2") -and -not (Test-Path "$Bundle\models\cellpose\cpsam_v2")) {
        Copy-Item "$ModelsFrom\cellpose\cpsam_v2" "$Bundle\models\cellpose\"
    }
    foreach ($d in "torch\hub", "pyconify") {
        if ((Test-Path "$ModelsFrom\$d") -and -not (Test-Path "$Bundle\models\$d\*")) {
            robocopy "$ModelsFrom\$d" "$Bundle\models\$d" /E /NFL /NDL /NJH /NJS /NP | Out-Null
        }
    }
}
if ($Plugins -contains "cellpose") {
    & $Py -c "from cellpose import models; models.CellposeModel(gpu=False)"; Check "cellpose model"
}
if ($Plugins -contains "convpaint") {
    # convpaint stores weights under TORCH_HOME only with this patch
    & $Py "$Bundle\scripts\patch_convpaint.py"; Check "patch_convpaint"
    & $Py -c "from napari_convpaint.convpaint_model import ConvpaintModel as M; m = M(); print('convpaint default:', m.get_param('fe_name'))"
    Check "convpaint default model"
}
if (-not (Test-Path "$Bundle\models\pyconify\sets\*.json")) {
    & $Py "$Bundle\scripts\download_icon_sets.py"; Check "icon sets"
}
& $Py "$Bundle\scripts\prefetch_icons.py" "$Bundle\faro"

# ---------------------------------------------------------------- 8. tidy up, README, check
Get-ChildItem "$Bundle\faro", "$Bundle\$LabDir" -Directory -Recurse -Force -Filter "__pycache__" | Remove-Item -Recurse -Force
foreach ($old in "env\.venv", "scripts\relocate.ps1", "BUNDLE_PATH.txt") {   # from the old venv layout
    if (Test-Path "$Bundle\$old") { Remove-Item "$Bundle\$old" -Recurse -Force }
}

$readme = @"
faro offline bundle: $LabPkg
==================================================
Built $(Get-Date -Format yyyy-MM-dd) by builder\build-bundle.ps1. Windows 10/11 x64.

Portable: copy the whole folder anywhere (other drive, USB stick, any name)
and start it there. Nothing has to be installed or fixed after copying.

Contents
  faro\  $LabDir\   git clones, editable: code changes apply directly
  python\           Python $PythonVersion with all packages (no venv)
  models\           model weights and GUI icons for offline use
  Plugins:          $($Plugins -join ', ')$(if ($ExtraPackages) { "`n  More packages:    $($ExtraPackages -join ', ')" })
  pymmcore:         $MMApi$(if ($needTorch) { "`n  torch:            $Torch" })
  Microscopes:      $($scopes -join ', ')
  faro:             $faroCommit
  $($LabDir.PadRight(17)) $labCommit
  pymmcore-widgets: $widgets

Install on the microscope PC (not in the bundle)
  - Micro-Manager 2.0 with the matching device interface, either installed
    (C:\Program Files\Micro-Manager-2.0) or as a folder named Micro-Manager*
    inside this folder or next to it (that one is used first)
  - the vendor drivers of the microscope's devices
  - git, only to pull/push the repositories

Start
  faro-napari.bat              double-click: $(if ($Microscope) { "starts $Microscope" } else { "lists the microscopes and asks" })
                               (change: the MICROSCOPE line at the top of the file)
  faro-napari.bat <microscope> a specific microscope
  napari.bat                   plain napari with all plugins, no microscope
                               (drag image files onto it to open them)$(if ($Plugins -contains 'jupyter') { "`n  jupyter-notebook.bat         Jupyter Notebook with this Python" })$(if ($Plugins -contains 'ipykernel') { "`n  VS Code notebooks:           python\python.exe is set as interpreter and kernel
                               (.vscode\settings.json in this folder, faro\, $LabDir\ and examples\)" })
  python-shell.bat             command prompt with this Python:  python my_script.py
  PowerShell with the bundle's paths:  . .\env.ps1   then   python my_script.py
  Check the bundle:            python\python.exe scripts\check_bundle.py

Update / rebuild (online)
  double-click builder\build-bundle.bat (the last choices are the defaults).
  It runs git pull in faro\ and $LabDir\ (a clone with local changes or local
  commits is left as it is) and resolves all packages again to their newest
  versions, the pymmcore-widgets build included. For the same package versions
  as this build: build-bundle.ps1 -KeepLock. Without git pull: -NoPull.
  python\python.exe finds models\ and a Micro-Manager* folder itself, however
  it is started (VS Code, Jupyter, .bat files): scripts\faro_bundle_env.py.
  Variables that are already set (by you or the system) win.
"@
[IO.File]::WriteAllText("$Bundle\README.txt", $readme, $NoBom)

Write-Host "`nChecking the bundle ..."
& $Py "$Bundle\scripts\check_bundle.py"
$ok = -not $LASTEXITCODE
$gb = (Get-ChildItem $Bundle -Recurse -File -Force | Measure-Object Length -Sum).Sum / 1GB
Write-Host ("`nBundle {0} in {1}. Size: {2:N1} GB" -f $(if ($ok) { "built" } else { "built WITH PROBLEMS (see above)" }), $Bundle, $gb)
Write-Host "  faro:             $faroCommit"
Write-Host "  $($LabDir.PadRight(17)) $labCommit"
Write-Host "  pymmcore-widgets: $widgets"

# ---------------------------------------------------------------- 9. self-extracting .exe
if ($Package -ne "none") {
    # The archive holds the bundle folder itself, so extracting to D:\ gives
    # D:\<bundle name>\... . 7z.sfx asks for the target folder when started.
    $exe = "$Bundle.exe"
    if (Test-Path $exe) { Remove-Item $exe -Force }
    $level = if ($Package -eq "normal") { "-mx=5" } else { "-mx=1" }
    Write-Host "`nPacking $exe ($Package) ..."
    Push-Location (Split-Path $Bundle -Parent)
    try {
        & $sevenZip a -t7z $level -mmt=on -bso0 -bsp1 "-sfx$(Join-Path (Split-Path $sevenZip) '7z.sfx')" `
            $exe (Split-Path $Bundle -Leaf); Check "7-Zip"
    } finally { Pop-Location }
    $exeGb = (Get-Item $exe).Length / 1GB
    Write-Host ("Self-extracting archive: {0} ({1:N1} GB)" -f $exe, $exeGb)
    # Windows does not start an .exe of 4 GB or more ("not a valid application").
    if ($exeGb -ge 4) { Write-Host "WARNING: 4 GB or more: Windows will not start this .exe. Copy the folder instead." }
    Write-Host "On the microscope PC: double-click it, choose the folder; it creates $(Split-Path $Bundle -Leaf)\ there."
}
