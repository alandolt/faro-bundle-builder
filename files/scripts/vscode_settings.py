"""Point VS Code to the bundle's Python (python\\python.exe). Idempotent.

    python\\python.exe scripts\\vscode_settings.py <folder> [<folder> ...]

Folders are relative to the bundle (e.g. "." faro faro-aoki faro-aoki\\examples).
Writes <folder>\\.vscode\\settings.json with a RELATIVE interpreter path, so it
keeps working when the bundle is moved:
    "python.defaultInterpreterPath": "${workspaceFolder}/../python/python.exe"
VS Code then uses this Python for scripts and as the notebook kernel.

An existing settings.json is never replaced: the key is only added if it is
missing and the file is plain JSON (a file with comments is left alone).
In git clones, .vscode/ is added to .git\\info\\exclude (local, never committed),
so the file does not show up in git status.
"""
import json
import pathlib
import sys

KEY = "python.defaultInterpreterPath"
bundle = pathlib.Path(__file__).resolve().parent.parent


def interpreter_path(folder: pathlib.Path) -> str:
    depth = len(folder.relative_to(bundle).parts)
    return "${workspaceFolder}/" + "../" * depth + "python/python.exe"


def git_exclude(folder: pathlib.Path) -> None:
    # the clone's root holds .git; folder may be a subfolder (e.g. examples)
    for root in (folder, *folder.parents):
        if root == bundle.parent:
            return
        info = root / ".git" / "info"
        if info.parent.is_dir():
            ex = info / "exclude"
            lines = ex.read_text(encoding="utf-8").splitlines() if ex.exists() else []
            if ".vscode/" not in lines:
                info.mkdir(exist_ok=True)
                with ex.open("a", encoding="utf-8", newline="\n") as f:
                    f.write(("\n" if lines and lines[-1] else "") + ".vscode/\n")
            return


for arg in sys.argv[1:]:
    folder = (bundle / arg).resolve()
    if not folder.is_dir():
        continue
    f = folder / ".vscode" / "settings.json"
    value = interpreter_path(folder)
    rel = f.relative_to(bundle)
    if not f.exists():
        f.parent.mkdir(exist_ok=True)
        f.write_text(json.dumps({KEY: value}, indent=4) + "\n", encoding="utf-8")
        print("[ok] written:", rel)
    else:
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except ValueError:
            print(f"[--] left alone (not plain JSON): {rel}. Add by hand: \"{KEY}\": \"{value}\"")
            data = None
        if isinstance(data, dict):
            if KEY in data:
                print(f"[ok] already set: {rel} ({data[KEY]})")
            else:
                data[KEY] = value
                f.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
                print("[ok] key added:", rel)
    git_exclude(folder)
