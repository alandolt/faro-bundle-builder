"""Hides the console window of a .bat once the napari window is open.

  python.exe -P scripts\\hide_console.py <module> [args]   runs "python -m <module> [args]"
  python.exe -P scripts\\hide_console.py --show            shows the console again

The console is only hidden when FARO_HIDE_CONSOLE=1 (the .bat sets it when it
was double-clicked, so a cmd window you typed the command in is not hidden).
If the program ends with an error, the .bat calls --show before its pause, so
the error stays readable.
"""

import ctypes
import os
import runpy
import sys
import threading
import time
from ctypes import wintypes

SW_HIDE = 0
SW_SHOW = 5
TITLE_PART = "napari"

kernel32 = ctypes.windll.kernel32
user32 = ctypes.windll.user32
kernel32.GetConsoleWindow.restype = wintypes.HWND
user32.EnumWindows.argtypes = [ctypes.c_void_p, wintypes.LPARAM]
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user32.IsWindowVisible.argtypes = [wintypes.HWND]
user32.InternalGetWindowText.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]

_ENUM_PROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)


def _napari_window_shown() -> bool:
    """True if this process has a visible top-level window with "napari" in its title."""
    pid = os.getpid()
    found = []

    def check(hwnd, _):
        if not user32.IsWindowVisible(hwnd):
            return True
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value != pid:
            return True
        # InternalGetWindowText does not send a message to the (maybe busy) GUI thread.
        buf = ctypes.create_unicode_buffer(256)
        user32.InternalGetWindowText(hwnd, buf, len(buf))
        if TITLE_PART in buf.value.lower():
            found.append(hwnd)
            return False
        return True

    user32.EnumWindows(_ENUM_PROC(check), 0)
    return bool(found)


def _hide_when_shown(console) -> None:
    while not _napari_window_shown():
        time.sleep(0.5)
    user32.ShowWindow(console, SW_HIDE)


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    console = kernel32.GetConsoleWindow()
    if sys.argv[1] == "--show":
        if console:
            user32.ShowWindow(console, SW_SHOW)
        return
    if console and os.environ.get("FARO_HIDE_CONSOLE") == "1":
        threading.Thread(target=_hide_when_shown, args=(console,), daemon=True).start()
    module = sys.argv[1]
    sys.argv = sys.argv[1:]
    runpy.run_module(module, run_name="__main__", alter_sys=True)


if __name__ == "__main__":
    main()
