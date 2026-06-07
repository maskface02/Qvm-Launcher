#!/usr/bin/env python3
"""
QVM Window Resizer
Finds the QEMU window and resizes it to fit the host screen.
Uses python-xlib so it works on X11 and XWayland (Wayland hosts).

CRITICAL: On HiDPI Wayland displays, X11 reports the *physical* pixel
size (e.g. 3072x1728 on a 1920x1080 logical screen). We must query
Mutter via DBus to get the *logical* size, otherwise the QEMU window
becomes larger than the screen.

Usage: qvm-resize-window.py "<vm-name>" [WxH]
"""

import sys
import os
import re
import subprocess
import time
from Xlib import X, XK, display, error


if len(sys.argv) < 2:
    print("Usage: qvm-resize-window.py <vm-name> [WxH]", file=sys.stderr)
    sys.exit(1)

VM_NAME = sys.argv[1]
REQUESTED = sys.argv[2] if len(sys.argv) > 2 else ""


def get_logical_screen_size():
    """Get the *logical* screen size, accounting for HiDPI scaling.

    Returns (width, height) in logical pixels. On standard 1.0x displays
    this matches the physical X11 size. On HiDPI Wayland (GNOME), the
    physical size from X11 is multiplied by the scale factor, so we
    query Mutter for the true logical resolution.
    """
    d = display.Display()
    root = d.screen().root
    phys_w = root.get_geometry().width
    phys_h = root.get_geometry().height
    d.close()

    # Try Mutter DisplayConfig (works on Wayland GNOME)
    try:
        result = subprocess.run(
            [
                "gdbus", "call", "--session",
                "--dest", "org.gnome.Mutter.DisplayConfig",
                "--object-path", "/org/gnome/Mutter/DisplayConfig",
                "--method", "org.gnome.Mutter.DisplayConfig.GetCurrentState",
            ],
            capture_output=True, text=True, timeout=3,
        )
        if result.returncode == 0 and result.stdout:
            # Find the current mode: '(WIDTHxHEIGHT@RATE' where is-current: true
            # The output is a giant nested tuple. Look for "WxH@" patterns
            # that have is-current nearby.
            text = result.stdout
            # Crude parse: find all "<W>x<H>@" patterns and pick the one
            # whose block contains "is-current"
            # Split by mode entries
            # The format is: ('WIDTHxHEIGHT@RATE', W, H, R, ...)
            mode_re = re.compile(r"'(\d+)x(\d+)@")
            # Find all matches and their positions
            matches = list(mode_re.finditer(text))
            for i, m in enumerate(matches):
                w, h = int(m.group(1)), int(m.group(2))
                # Look ahead ~200 chars for "is-current" true
                end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
                chunk = text[m.start():end]
                if "is-current" in chunk and "true" in chunk[chunk.find("is-current"):]:
                    print(f"Host screen (Mutter): {w}x{h} (X11 physical was {phys_w}x{phys_h})")
                    return w, h
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    # Fall back to physical X11 size (correct on non-HiDPI X11 sessions)
    print(f"Host screen (X11): {phys_w}x{phys_h}")
    return phys_w, phys_h


def find_window(d, root, target_name):
    """Find a top-level window whose WM_NAME contains target_name."""
    try:
        children = root.query_tree().children
    except Exception:
        return None
    for w in children:
        try:
            name = w.get_wm_name()
            if isinstance(name, bytes):
                name = name.decode("utf-8", errors="replace")
            if name and target_name in name:
                return w
        except (error.BadWindow, error.BadAccess):
            continue
    return None


def main():
    screen_w, screen_h = get_logical_screen_size()

    # Wait for the QEMU window to appear
    d = display.Display()
    root = d.screen().root
    target = f"QVM - {VM_NAME}"
    win = None
    for attempt in range(40):  # up to 20 seconds
        win = find_window(d, root, target)
        if win:
            break
        time.sleep(0.5)

    if not win:
        print(f"Error: window '{target}' not found after 20s", file=sys.stderr)
        d.close()
        sys.exit(1)

    # Determine target size: smaller of (screen, REQUESTED) so it always fits
    target_w = screen_w
    target_h = screen_h

    if REQUESTED and "x" in REQUESTED:
        try:
            req_w, req_h = REQUESTED.lower().split("x", 1)
            req_w = int(req_w)
            req_h = int(req_h)
            if req_w < screen_w:
                target_w = req_w
            if req_h < screen_h:
                target_h = req_h
        except ValueError:
            print(f"Warning: bad VM_GEOMETRY '{REQUESTED}', using screen size")

    # Leave a small margin for WM titlebar and borders
    win_w = target_w - 20
    win_h = target_h - 60

    # Enforce a minimum usable size
    if win_w < 800:
        win_w = 800
    if win_h < 600:
        win_h = 600

    # Don't make it larger than the screen minus margins
    if win_w > screen_w - 20:
        win_w = screen_w - 20
    if win_h > screen_h - 60:
        win_h = screen_h - 60

    try:
        win.configure(width=win_w, height=win_h)
        d.sync()
        print(f"Resized QEMU window to {win_w}x{win_h}")
    except Exception as e:
        print(f"Warning: resize failed: {e}", file=sys.stderr)
        d.close()
        sys.exit(1)

    d.close()


if __name__ == "__main__":
    main()
