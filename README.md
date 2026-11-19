# faro-bundle-builder

Builds a portable offline bundle of [faro](https://github.com/alandolt/faro) for a
microscope PC (Windows 10/11 x64): Python 3.12, faro and a lab package
(faro-aoki, faro-pertzlab or another git URL) as editable git clones, a choice
of napari plugins, the cellpose / convpaint models and the GUI icons. It can
also pack the bundle as one self-extracting `.exe` (7-Zip).

The bundle has no venv: everything is installed into its own `python\`, so the
folder can be moved to any path or drive.

## Use

Double-click `build-bundle.bat`, or:

```bat
powershell -ExecutionPolicy Bypass -File build-bundle.ps1 -Lab aoki -Yes
```

Needs uv and git on PATH; 7-Zip for the `.exe`. The parameters are listed at
the top of `build-bundle.ps1`. Run it again on an existing bundle to update it
(the last choices are saved in `bundle-config.json` and are the defaults).

## Layout

- `build-bundle.ps1`: the builder; `build-bundle.bat` starts it
- `files\`: copied into every bundle (launchers, `env.ps1`, helper scripts)
  - `scripts\check_bundle.py`: checks a finished bundle
  - `scripts\faro_bundle_env.py`: the bundle's Python finds its models and a
    `Micro-Manager*` folder itself
  - `scripts\vscode_settings.py`: VS Code uses the bundle's Python

The Windows 7 bundle (`C:\faro-aoki-w7`) is built separately, see its
`BUILD-WIN7.txt`.
