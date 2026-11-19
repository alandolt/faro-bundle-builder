"""Install faro_bundle_env (+ .pth) into the running Python. Idempotent.

After this, the bundle's Python sets CELLPOSE_LOCAL_MODELS_PATH, TORCH_HOME
and MICROMANAGER_PATH itself at every start (see faro_bundle_env.py).
"""
import pathlib
import shutil
import sysconfig

sp = pathlib.Path(sysconfig.get_paths()["purelib"])
here = pathlib.Path(__file__).parent
shutil.copy2(here / "faro_bundle_env.py", sp / "faro_bundle_env.py")
(sp / "faro_bundle_env.pth").write_text("import faro_bundle_env\n", encoding="ascii")
print("[ok] bundle variables installed in", sp)
