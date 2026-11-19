"""Download every iconify icon used by the GUI packages into PYCONIFY_CACHE.

Run ONLINE with the python of each env (tool and faro venv), after
install_offline_icons.py, so PYCONIFY_CACHE points to <bundle>\\models\\pyconify.
Icon names are collected from the source of the packages below; only the plain
(uncolored) icon is needed, faro_offline_icons makes colored variants offline.
"""
import pathlib
import re
import sys
import sysconfig

import pyconify

PACKAGES = ("pymmcore_widgets", "napari_micromanager", "superqt", "faro")
key_re = re.compile(r"""["']([a-z0-9]+(?:-[a-z0-9]+)*:[a-z0-9]+(?:-[a-z0-9]+)*)["']""")

roots = [pathlib.Path(sysconfig.get_paths()["purelib"])] + [pathlib.Path(p) for p in sys.argv[1:]]
# Real icon-set prefixes, so that any "prefix:name" string can be checked (icon
# names are often defined in files that do not mention iconify themselves).
try:
    prefixes = set(pyconify.collections())
except Exception:
    prefixes = None  # API unreachable: fall back to files that mention iconify
keys = set()
for root in roots:
    for pkg in PACKAGES:
        for f in (root / pkg).rglob("*.py") if (root / pkg).is_dir() else []:
            src = f.read_text(encoding="utf-8", errors="ignore")
            if prefixes is None and not re.search(r"iconify|pyconify|QIconifyIcon", src, re.I):
                continue
            for k in key_re.findall(src):
                if k.startswith("prefix:") or (prefixes is not None and k.split(":")[0] not in prefixes):
                    continue
                keys.add(k)

import time

import requests

print("cache:", pyconify.get_cache_directory(), "| icons:", len(keys))
failed = []
for key in sorted(keys):
    for attempt in range(4):
        try:
            pyconify.svg_path(key)
            break
        except OSError as e:
            # pyconify reports every 4xx as "not found"; the API rate-limits with 429
            prefix, name = key.split(":", 1)
            try:
                r = requests.get(f"https://api.iconify.design/{prefix}/{name}.svg", timeout=20)
            except requests.RequestException:  # slow/unreachable server: wait and retry
                if attempt < 3:
                    print("  server not responding, waiting 30 s ...", flush=True)
                    time.sleep(30)
                    continue
                failed.append(f"{key} (no response: {str(e)[:50]})")
                break
            if r.status_code == 429 and attempt < 3:
                wait = int(r.headers.get("Retry-After", "60")) + 2
                print(f"  rate limited, waiting {wait} s ...", flush=True)
                time.sleep(wait)
                continue
            failed.append(f"{key} ({r.status_code}: {str(e)[:50]})")
            break
    time.sleep(0.5)  # be gentle with the free API
print(f"{len(keys) - len(failed)} icons cached, {len(failed)} not found")
for f in failed:
    print("   ", f)
