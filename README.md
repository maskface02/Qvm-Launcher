# QVM Launcher

A simple script to launch QEMU/KVM VMs with SPICE support.

## Requirements
- QEMU/KVM (qemu-system-x86_64, qemu-img)
- SPICE client (remote-viewer, usually in virt-viewer)
- Audio system (pulseaudio, alsa-utils, or pipewire)
- Linux host with KVM support

## Usage
Boot existing VM:
```bash
./qvm-launcher.sh <vm-name>
```
Looks for: `./<vm-name>/<vm-name>.qcow2`

Create new VM and boot installer:
```bash
./qvm-launcher.sh -f <vm-name> <path-to-installer.iso>
```
Creates: `./<vm-name>/<vm-name>.qcow2` if missing.

List available VMs:
```bash
./qvm-launcher.sh --list
```

## Features
- Interactive configuration for RAM, storage, CPU cores (only when creating VM)
- Auto-detects host threads per core (no prompt)
- Saves VM configuration for consistent boots
- SPICE support for clipboard and display resolution
- Shell autocompletion (bash/zsh/fish) via `./qvm-launcher.sh --install-completion`

## SPICE Guest Agent
For clipboard and dynamic resolution, install the spice-vdagent inside the VM:
See [SPICE-GUEST-SETUP.md](SPICE-GUEST-SETUP.md) for detailed installation and service management instructions.