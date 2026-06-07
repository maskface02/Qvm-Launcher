#!/usr/bin/env python3
"""
QVM Guest Resolution Setter
Uses the QEMU Guest Agent (qemu-guest-agent running inside the VM) to
change the guest's display resolution. This causes QEMU GTK to resize
its window to match the new guest mode.

Requires: qemu-guest-agent installed and running inside the guest:
  - Arch/CachyOS:  sudo pacman -S qemu-guest-agent
                   sudo systemctl enable --now qemu-guest-agent.service
  - Debian/Ubuntu: sudo apt install qemu-guest-agent
                   sudo systemctl enable --now qemu-guest-agent.service

Usage: qvm-set-resolution.py <socket> <WxH> [output]
Example: qvm-set-resolution.py /tmp/qvm-qga.sock 1366x768 Virtual-1
"""

import sys
import os
import json
import socket
import time
import subprocess


def find_xrandr_output():
    """Try to discover the right xrandr output name in the guest.

    Strategy: ask the guest agent to run `xrandr -q` and parse the
    connected output name.
    """
    return None  # Caller supplies output; we just try Virtual-1 first


def send_qga_command(sock, command):
    """Send a QMP command to the guest agent and return the response."""
    sock.sendall((json.dumps(command) + "\n").encode("utf-8"))
    # Read until newline
    chunks = []
    sock.settimeout(10)
    try:
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
            if b"\n" in chunk:
                break
    except socket.timeout:
        pass
    return b"".join(chunks).decode("utf-8", errors="replace")


def try_xrandr(sock, resolution, output):
    """Send xrandr command via the guest agent."""
    res_w, res_h = resolution.split("x", 1)
    cmd = {
        "execute": "guest-exec",
        "arguments": {
            "path": "/usr/bin/xrandr",
            "arg": ["--output", output, "--mode", f"{res_w}x{res_h}"],
            "capture-output": True,
        },
    }
    return send_qga_command(sock, cmd)


def try_wayland_gsettings(sock, resolution):
    """For Wayland GNOME guests: use gsettings to set display resolution
    via mutter's experimental-features."""
    res_w, res_h = resolution.split("x", 1)
    # mutter doesn't have a public gsettings for resolution. Try
    # gnome-randr (not standard) or just fail gracefully.
    return None


def main():
    if len(sys.argv) < 3:
        print("Usage: qvm-set-resolution.py <socket> <WxH> [output]", file=sys.stderr)
        sys.exit(1)

    sock_path = sys.argv[1]
    resolution = sys.argv[2]
    output = sys.argv[3] if len(sys.argv) > 3 else "Virtual-1"

    # Wait for the guest agent socket to be ready (up to 60s)
    s = None
    for _ in range(60):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(5)
            s.connect(sock_path)
            break
        except (FileNotFoundError, ConnectionRefusedError, OSError):
            if s:
                s.close()
            s = None
            time.sleep(1)

    if s is None:
        print(f"guest agent socket not available: {sock_path}", file=sys.stderr)
        print("(Is qemu-guest-agent installed and running in the guest?)",
              file=sys.stderr)
        sys.exit(1)

    try:
        # Drain the initial greeting (the agent sends {"return": {...}})
        s.settimeout(2)
        try:
            s.recv(4096)
        except socket.timeout:
            pass

        # Try xrandr first
        print(f"Setting guest resolution to {resolution} on output '{output}'",
              flush=True)
        response = try_xrandr(s, resolution, output)
        print(f"Guest agent response: {response.strip()}", flush=True)
    finally:
        s.close()


if __name__ == "__main__":
    main()
