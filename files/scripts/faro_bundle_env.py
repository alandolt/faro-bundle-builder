"""Bundle variables, set by the bundle's Python itself at every start.

Installed into site-packages with faro_bundle_env.pth (scripts\\install_bundle_env.py).
Python then finds the bundle's models and Micro-Manager however it is started:
from VS Code (notebook kernels, the debugger), Jupyter, the .bat files or a
plain command prompt. Paths are found relative to python\\, so the bundle
stays portable.

Only variables that are not set yet are filled in: values from the user, the
.bat files (scripts\\bundle-env.bat) or the system always win. Never raises, so
it cannot stop Python from starting.
"""


def _setup():
    import os
    import pathlib
    import sys

    # <bundle>\python is sys.base_prefix (also inside a venv made from it)
    bundle = pathlib.Path(sys.base_prefix).parent
    models = bundle / "models"
    if not models.is_dir():
        return  # not the bundle's Python layout: do nothing
    os.environ.setdefault("CELLPOSE_LOCAL_MODELS_PATH", str(models / "cellpose"))
    os.environ.setdefault("TORCH_HOME", str(models / "torch"))
    # Micro-Manager, same order as bundle-env.bat: an already set
    # MICROMANAGER_PATH wins; then a Micro-Manager* folder inside the bundle;
    # then one next to it. Otherwise the microscope class's own path is used.
    if not os.environ.get("MICROMANAGER_PATH"):
        for parent in (bundle, bundle.parent):
            found = sorted(p for p in parent.glob("Micro-Manager*") if p.is_dir())
            if found:
                os.environ["MICROMANAGER_PATH"] = str(found[0])
                break


try:
    _setup()
except Exception:  # noqa: BLE001
    pass
