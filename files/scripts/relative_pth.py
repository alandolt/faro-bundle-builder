"""Rewrite absolute paths inside the bundle in site-packages\\*.pth as relative ones.

uv writes the editable installs of faro / faro-aoki as .pth files with absolute
paths (e.g. C:\\faro-aoki\\faro). Python's site module reads a relative .pth line
relative to site-packages, so "..\\..\\..\\faro" works wherever the bundle is.
Run with the bundle's python after every uv sync. Idempotent.
"""
import os
import sysconfig

sp = sysconfig.get_paths()["purelib"]
bundle = os.path.normcase(os.path.abspath(os.path.join(sp, "..", "..", "..")))

for name in sorted(os.listdir(sp)):
    if not name.endswith(".pth"):
        continue
    fn = os.path.join(sp, name)
    with open(fn, encoding="utf-8") as f:
        lines = f.read().splitlines()
    new = []
    for line in lines:
        s = line.strip()
        if s and not s.startswith(("#", "import ")) and os.path.isabs(s):
            full = os.path.abspath(s)
            nc = os.path.normcase(full)
            if nc == bundle or nc.startswith(bundle + os.sep):
                line = os.path.relpath(full, sp)
        new.append(line)
    if new != lines:
        with open(fn, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(new) + "\n")
        print("[ok] relative paths:", name, "->", ", ".join(new))
