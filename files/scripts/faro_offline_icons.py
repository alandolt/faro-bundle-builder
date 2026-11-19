"""Offline support for pyconify (the icon source of superqt.QIconifyIcon,
used by pymmcore-widgets / napari-micromanager).

Loaded at interpreter start via faro_offline_icons.pth. It
  1. points pyconify's SVG cache to <bundle>\\models\\pyconify (pre-filled by
     scripts\\prefetch_icons.py), unless PYCONIFY_CACHE is already set;
  2. once pyconify.api is imported, patches it so that
     - every icon of a complete set in models\\pyconify\\sets\\<prefix>.json
       (scripts\\download_icon_sets.py) is built locally, incl. color/flip/rotate,
       without any network access;
     and for other sets, without internet
     - the icon-set date lookup (last_modified) is tried once, not per icon;
     - an icon in a color/variant that is not cached is made from the cached
       plain icon by replacing "currentColor" locally (what the iconify server
       does as well). Flip/rotate are not applied in that case.
The path is relative (this file sits in <env>\\Lib\\site-packages, 4 levels below
the bundle root, for faro\\.venv and tools\\<name> alike).
"""
import importlib.abc
import importlib.machinery
import os
import sys

# The bundle root is the first parent folder with models\pyconify in it
# (python\Lib\site-packages -> 3 levels up; an old env\.venv layout -> 4).
_CACHE = ""
_d = os.path.dirname(os.path.abspath(__file__))
for _ in range(6):
    _d = os.path.dirname(_d)
    if os.path.isdir(os.path.join(_d, "models", "pyconify")):
        _CACHE = os.path.join(_d, "models", "pyconify")
        break
if os.path.isdir(_CACHE):
    os.environ.setdefault("PYCONIFY_CACHE", _CACHE)


def _patch(api):
    orig_last_modified = api.last_modified
    orig_svg = api.svg
    state = {"offline": False}

    def last_modified(*prefixes):
        if state["offline"]:
            return {}
        try:
            return orig_last_modified(*prefixes)
        except OSError:  # no network (requests errors are OSErrors)
            state["offline"] = True
            raise  # callers already handle OSError -> "no date" (offline lookup)

    def svg(*key, color=None, height=None, width=None, flip=None, rotate=None, box=None):
        # 1. complete icon set in models\pyconify\sets: build locally, never online
        try:
            prefix, name = api._split_prefix_name(key)
            data = _from_set(prefix, name, color, height, width, flip, rotate)
        except Exception:
            data = None
        if data is not None:
            return data
        if state["offline"]:  # known offline: don't wait for the network again
            data = _local_variant(api, key, color)
            if data is not None:
                return data
        try:
            return orig_svg(*key, color=color, height=height, width=width,
                            flip=flip, rotate=rotate, box=box)
        except OSError as err:
            data = _local_variant(api, key, color)
            if data is None:
                raise err
            state["offline"] = True
            return data

    # pyconify/__init__ imports these names from api after this runs
    api.last_modified = last_modified
    api.svg = svg


_SETS = {}


def _load_set(prefix):
    if prefix not in _SETS:
        import json
        fn = os.path.join(_CACHE, "sets", prefix + ".json")
        try:
            with open(fn, encoding="utf-8") as f:
                _SETS[prefix] = json.load(f)
        except (OSError, ValueError):
            _SETS[prefix] = None
    return _SETS[prefix]


def _ceil(v):  # iconify rounds sizes up to 2 decimals
    import math
    return f"{math.ceil(v * 100) / 100:g}"


def _num(v):
    return f"{v:g}" if isinstance(v, float) else str(v)


def _from_set(prefix, name, color=None, height=None, width=None, flip=None, rotate=None):
    """Build the SVG like api.iconify.design does, from a downloaded icon set."""
    data = _load_set(prefix)
    if not data:
        return None
    icons, aliases = data.get("icons", {}), data.get("aliases", {})
    # resolve aliases (they may add flips/rotation)
    props, hflip, vflip, rot, seen = {}, False, False, 0, set()
    while name not in icons:
        a = aliases.get(name)
        if a is None or name in seen:
            return None
        seen.add(name)
        for k in ("left", "top", "width", "height"):
            props.setdefault(k, a.get(k))
        hflip ^= bool(a.get("hFlip"))
        vflip ^= bool(a.get("vFlip"))
        rot += int(a.get("rotate", 0))
        name = a["parent"]
    icon = icons[name]
    box = {k: props.get(k) if props.get(k) is not None else icon.get(k, data.get(k, d))
           for k, d in (("left", 0), ("top", 0), ("width", 16), ("height", 16))}
    body = icon["body"]
    # requested flip/rotate
    f = str(flip or "")
    c_h, c_v = "horizontal" in f, "vertical" in f
    if rotate in (None, ""):
        c_rot = 0
    elif rotate in (1, 2, 3):
        c_rot = int(rotate)
    else:
        c_rot = int(float(str(rotate).replace("deg", ""))) // 90
    for h, v, r in ((hflip ^ bool(icon.get("hFlip")), vflip ^ bool(icon.get("vFlip")),
                     rot + int(icon.get("rotate", 0))), (c_h, c_v, c_rot)):
        tr = []
        if h:
            if v:
                r += 2
            else:
                tr += [f"translate({_num(box['width'] + box['left'])} {_num(-box['top'])})", "scale(-1 1)"]
                box["top"] = box["left"] = 0
        elif v:
            tr += [f"translate({_num(-box['left'])} {_num(box['height'] + box['top'])})", "scale(1 -1)"]
            box["top"] = box["left"] = 0
        r %= 4
        if r == 1:
            t = box["height"] / 2 + box["top"]
            tr.insert(0, f"rotate(90 {_num(t)} {_num(t)})")
        elif r == 2:
            tr.insert(0, f"rotate(180 {_num(box['width'] / 2 + box['left'])} {_num(box['height'] / 2 + box['top'])})")
        elif r == 3:
            t = box["width"] / 2 + box["left"]
            tr.insert(0, f"rotate(-90 {_num(t)} {_num(t)})")
        if r % 2:
            box["left"], box["top"] = box["top"], box["left"]
            box["width"], box["height"] = box["height"], box["width"]
        if tr:
            body = f'<g transform="{" ".join(tr)}">{body}</g>'
    ratio = box["width"] / box["height"]

    def em(v):
        return f"{_ceil(v)}em"
    if width is None and height is None:
        h_attr, w_attr = "1em", em(ratio)
    elif width is None:
        h_attr = str(height)
        w_attr = _ceil(float(height) * ratio) if str(height).replace(".", "").isdigit() else h_attr
    elif height is None:
        w_attr = str(width)
        h_attr = _ceil(float(width) / ratio) if str(width).replace(".", "").isdigit() else w_attr
    else:
        w_attr, h_attr = str(width), str(height)
    xlink = ' xmlns:xlink="http://www.w3.org/1999/xlink"' if "xlink:" in body else ""
    vb = " ".join(_num(box[k]) for k in ("left", "top", "width", "height"))
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg"{xlink} width="{w_attr}" '
           f'height="{h_attr}" viewBox="{vb}">{body}</svg>')
    if color:
        svg = svg.replace("currentColor", str(color))
    return svg.encode()


def _local_variant(api, key, color):
    """Build an icon from any cached version of the same icon."""
    try:
        prefix, name = api._split_prefix_name(key)
        cache = api.svg_cache()
        path = getattr(cache, "path", None)
    except Exception:
        return None
    if path is None or not os.path.isdir(path):
        return None
    stem = f"{prefix}_{name}_"
    plain, other = None, None
    for fn in os.listdir(path):
        if not (fn.startswith(stem) and fn.endswith(".svg")):
            continue
        rest = fn[len(stem):-4]
        if rest.isdigit():  # "<prefix>_<name>_<lastmod>.svg" = plain icon
            plain = fn
            break
        other = other or fn
    fn = plain or other
    if fn is None:
        return None
    with open(os.path.join(path, fn), "rb") as f:
        data = f.read()
    if color and plain:
        data = data.replace(b"currentColor", str(color).encode())
    return data


class _PatchAfterImport(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path=None, target=None):
        if fullname != "pyconify.api":
            return None
        spec = importlib.machinery.PathFinder.find_spec(fullname, path)
        if spec is None or spec.loader is None:
            return None
        exec_module = spec.loader.exec_module

        def exec_and_patch(module):
            exec_module(module)
            try:
                _patch(module)
            except Exception as e:  # never break the app because of icons
                print(f"faro_offline_icons: patch failed: {e}", file=sys.stderr)

        spec.loader.exec_module = exec_and_patch
        return spec


if not any(type(f).__name__ == "_PatchAfterImport" for f in sys.meta_path):
    sys.meta_path.insert(0, _PatchAfterImport())
