"""Check the portable faro bundle. Prints only, changes nothing.

    python\\python.exe scripts\\check_bundle.py      (or check-bundle.bat)

Run at the end of build-bundle.ps1 as well. Exit code 1 if a check failed.
"""
import os
import pathlib
import sys
import sysconfig

bundle = pathlib.Path(__file__).resolve().parent.parent
sp = pathlib.Path(sysconfig.get_paths()["purelib"])
failed = []


def check(name, cond, detail=""):
    if not cond:
        failed.append(name)
    print(f"  [{'OK' if cond else '!!'}] {name}" + (f": {detail}" if detail else ""))


def inside(p):
    return pathlib.Path(p).resolve().is_relative_to(bundle)


print("bundle:", bundle)
print("python:", sys.executable)
check("python of the bundle, no venv", inside(sys.executable) and sys.prefix == sys.base_prefix)

# Editable faro / lab package: .pth lines must be relative (portable folder)
absolute = [p.name for p in sp.glob("*.pth")
            for line in p.read_text(encoding="utf-8", errors="ignore").splitlines()
            if line.strip() and not line.startswith(("#", "import")) and os.path.isabs(line.strip())]
check("no absolute paths in site-packages\\*.pth", not absolute, ", ".join(absolute))

import faro  # noqa: E402

check("faro from the bundle", inside(faro.__file__), faro.__file__)
from faro.microscope.registry import available_scopes  # noqa: E402

scopes = sorted(available_scopes())
check("microscopes registered", scopes, " ".join(scopes))

# Models (only for the plugins in this bundle)
import importlib.util  # noqa: E402

if importlib.util.find_spec("cellpose"):
    check("cellpose-SAM model", (bundle / "models/cellpose/cpsam_v2").exists())
if importlib.util.find_spec("napari_convpaint"):
    ckpt = list((bundle / "models/torch").rglob("*.pt*"))
    check("convpaint weights (models\\torch)", ckpt, f"{len(ckpt)} files")

# Offline icons
check("icon module installed", (sp / "faro_offline_icons.pth").exists())
check("icon module active", "faro_offline_icons" in sys.modules)
check("PYCONIFY_CACHE in the bundle", inside(os.environ.get("PYCONIFY_CACHE", "/")),
      os.environ.get("PYCONIFY_CACHE"))
sets = sorted(p.stem for p in (bundle / "models/pyconify/sets").glob("*.json"))
check("icon sets", sets, " ".join(sets))

# Bundle variables: set by python itself (faro_bundle_env), also without the
# .bat files, e.g. for a VS Code notebook kernel. Checked in a fresh python
# started from another folder, with the variables removed.
import json  # noqa: E402
import subprocess  # noqa: E402
import tempfile  # noqa: E402

check("bundle variables installed", (sp / "faro_bundle_env.pth").exists())
names = ["CELLPOSE_LOCAL_MODELS_PATH", "TORCH_HOME", "MICROMANAGER_PATH"]
clean = {k: v for k, v in os.environ.items() if k not in names}
code = f"import os, json; print(json.dumps({{k: os.environ.get(k) for k in {names!r}}}))"
out = subprocess.run([sys.executable, "-c", code], env=clean, cwd=tempfile.gettempdir(),
                     capture_output=True, text=True)
got = json.loads(out.stdout or "{}")
for k in names[:2]:
    check(f"{k} without .bat", bool(got.get(k)) and inside(got[k]), got.get(k))
print("  [..] MICROMANAGER_PATH without .bat:",
      got.get("MICROMANAGER_PATH") or "(no Micro-Manager* folder; the microscope class decides)")

# VS Code settings: the interpreter path must lead to this python
vs = [f for pat in (".vscode", "*/.vscode", "*/examples/.vscode")
      for f in sorted(bundle.glob(pat + "/settings.json"))]
check("VS Code settings", vs, f"{len(vs)} folders")
for f in vs:
    folder = f.parent.parent
    try:
        v = json.loads(f.read_text(encoding="utf-8")).get("python.defaultInterpreterPath", "")
    except ValueError:
        v = ""
    if not v.startswith("${workspaceFolder}"):
        print(f"  [..] VS Code {folder.relative_to(bundle)}: own settings ({v or 'no interpreter path'})")
        continue
    target = pathlib.Path(v.replace("${workspaceFolder}", str(folder))).resolve()
    check(f"VS Code interpreter in {folder.relative_to(bundle)}",
          target == pathlib.Path(sys.executable).resolve(), v)

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from qtpy.QtWidgets import QApplication  # noqa: E402
from superqt import QIconifyIcon  # noqa: E402

app = QApplication([])
for key, color in [("mdi:camera-outline", "green"), ("mdi:hexagon-outline", "green"),
                   ("mdi:hexagon-slice-6", "gray"), ("mdi:rocket-launch", "blue")]:
    img = QIconifyIcon(key, color=color).pixmap(32, 32).toImage()
    drawn = sum(img.pixelColor(x, y).alpha() > 0 for x in range(32) for y in range(32))
    check(f"render {key} ({color})", drawn)

print("\nALL OK" if not failed else f"\n{len(failed)} CHECK(S) FAILED: " + ", ".join(failed))
sys.exit(1 if failed else 0)
