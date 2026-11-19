"""Download complete iconify icon sets (all icons of a prefix) for offline use.

Run ONLINE:   <python> scripts\\download_icon_sets.py            (sets used by the GUI)
              <python> scripts\\download_icon_sets.py mdi tabler  (these sets in addition)
              <python> scripts\\download_icon_sets.py --all       (every iconify set, ~400 MB)
Saves <bundle>\\models\\pyconify\\sets\\<prefix>.json (iconify JSON format).
faro_offline_icons builds any icon of these sets locally (color, flip, rotate),
so no icon has to be fetched from api.iconify.design.
"""
import json
import pathlib
import re
import sys
import sysconfig
import time

import requests

BUNDLE = pathlib.Path(__file__).resolve().parent.parent
OUT = BUNDLE / "models" / "pyconify" / "sets"
# Sets used by pymmcore-widgets / napari-micromanager / superqt / faro, plus common ones
DEFAULT = ["bi", "carbon", "fa6-solid", "fa6-regular", "fluent", "ic", "majesticons",
           "mdi", "mdi-light", "mynaui", "ph", "material-symbols", "tabler", "lucide"]
PACKAGES = ("pymmcore_widgets", "napari_micromanager", "superqt", "faro")
URLS = ["https://cdn.jsdelivr.net/npm/@iconify-json/{p}/icons.json",
        "https://raw.githubusercontent.com/iconify/icon-sets/master/json/{p}.json"]
HEADERS = {"User-Agent": "faro-offline-bundle"}


def get(url, tries=4):
    for attempt in range(tries):
        try:
            r = requests.get(url, headers=HEADERS, timeout=120)
            if r.status_code == 429 and attempt < tries - 1:
                time.sleep(int(r.headers.get("Retry-After", "30")) + 2)
                continue
            return r
        except requests.RequestException:
            if attempt == tries - 1:
                raise
            time.sleep(10)


def prefixes_in_sources():
    """Prefixes of cached icons and of "prefix:name" strings in the GUI packages."""
    found = set()
    cache = OUT.parent / "svg_cache"
    if cache.is_dir():
        found |= {f.name.split("_")[0] for f in cache.glob("*.svg")}
    key_re = re.compile(r"""["']([a-z0-9]+(?:-[a-z0-9]+)*):[a-z0-9]+(?:-[a-z0-9]+)*["']""")
    roots = [pathlib.Path(sysconfig.get_paths()["purelib"]), BUNDLE]
    cands = set()
    for root in roots:
        for pkg in PACKAGES:
            d = root / pkg
            for f in d.rglob("*.py") if d.is_dir() else []:
                cands |= set(key_re.findall(f.read_text(encoding="utf-8", errors="ignore")))
    try:  # keep only real iconify prefixes
        r = get("https://api.iconify.design/collections")
        found |= cands & set(r.json())
    except Exception:
        pass
    return found


def main(argv):
    if "--all" in argv:
        r = get("https://raw.githubusercontent.com/iconify/icon-sets/master/collections.json")
        r.raise_for_status()
        wanted = set(r.json())
    else:
        wanted = set(DEFAULT) | prefixes_in_sources() | {a for a in argv if not a.startswith("-")}
    OUT.mkdir(parents=True, exist_ok=True)
    print(f"{len(wanted)} icon sets -> {OUT}", flush=True)
    failed = []
    for p in sorted(wanted):
        data = None
        for url in URLS:
            try:
                r = get(url.format(p=p))
            except requests.RequestException:
                continue
            if r.status_code == 200:
                try:
                    data = r.json()
                    break
                except ValueError:
                    pass
        if not data or "icons" not in data:
            failed.append(p)
            print(f"  {p}: FAILED", flush=True)
            continue
        tmp = OUT / f"{p}.json.tmp"
        tmp.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
        tmp.replace(OUT / f"{p}.json")
        n = len(data["icons"]) + len(data.get("aliases", {}))
        print(f"  {p}: {n} icons", flush=True)
    print(f"done, {len(wanted) - len(failed)} sets saved, {len(failed)} failed {failed or ''}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
