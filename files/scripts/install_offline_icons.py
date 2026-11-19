"""Install faro_offline_icons (+ .pth) into the env of the running python. Idempotent."""
import pathlib
import shutil
import sysconfig

sp = pathlib.Path(sysconfig.get_paths()["purelib"])
here = pathlib.Path(__file__).parent
shutil.copy2(here / "faro_offline_icons.py", sp / "faro_offline_icons.py")
(sp / "faro_offline_icons.pth").write_text("import faro_offline_icons\n", encoding="ascii")
(here.parent / "models" / "pyconify").mkdir(parents=True, exist_ok=True)
print("[ok] offline icons installed in", sp)
