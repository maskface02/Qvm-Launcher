# QVM Launcher - QEMU Virtual Machine Launcher

A user-friendly script to launch QEMU virtual machines with SPICE for remote desktop access. Features interactive configuration for RAM, storage, and CPU settings, automatic CPU thread detection, and seamless SPICE integration.

## Features

- **Interactive Configuration**: Prompt for RAM, storage, and CPU cores when creating new VMs
- **Smart Defaults**: Uses sensible defaults when booting existing VMs (no prompts)
- **Auto-detect CPU Threads**: Automatically detects threads per core from host CPU
- **CPU Compatibility**: Works with both AMD and Intel processors using `-cpu host`
- **SPICE Integration**: Remote desktop access with clipboard sharing (requires `spice-vdagent` in guest)
- **Enhanced Display Support**: Increased QXL resources for better resolution support
- **Dependency Checking**: Verifies required tools and provides installation guidance
- **Proper Cleanup**: Ensures QEMU process and SPICE socket are cleaned up on exit
- **Helpful Messages**: Informs users about installing SPICE guest agents for optimal functionality

## Requirements

- QEMU/KVM (`qemu-system-x86_64`, `qemu-img`)
- SPICE client (`remote-viewer` from virt-viewer package)
- Audio system (PipeWire, PulseAudio, or ALSA)
- Linux system with bash

## Installation

1. **Install required packages**:

   **Debian/Ubuntu**:
   ```bash
   sudo apt update
   sudo apt install -y qemu-system-x86 qemu-utils virt-viewer
   ```

   **Arch Linux**:
   ```bash
   sudo pacman -Sy --needed qemu virt-viewer
   ```

   **Fedora**:
   ```bash
   sudo dnf install -y @virtualization virt-viewer
   ```

   **openSUSE**:
   ```bash
   sudo zypper install -y qemu-x86 virt-viewer
   ```

2. **Enable KVM access without sudo** (recommended):
   ```bash
   sudo adduser $USER kvm
   # Then log out and log back in for group changes to take effect
   ```

3. **Make the script executable**:
   ```bash
   chmod +x qvm-launcher.sh
   ```

## Usage

### Boot an Existing VM
```bash
./qvm-launcher.sh <path-to-vm.qcow2>
```
- Uses default settings: 8GB RAM, 4 CPU cores, auto-detected threads per core
- No configuration prompts - boots immediately with sensible defaults

### Create New VM and Install from ISO
```bash
./qvm-launcher.sh -f <path-to-new-vm.qcow2> <path-to-installer.iso>
```
- Prompts for:
  - RAM size in GB (default: 8GB)
  - Storage size in GB (default: 100GB)
  - Number of CPU cores (default: 4)
- Automatically detects threads per core from host CPU
- Creates the disk image if it doesn't exist
- Boots from the ISO for installation

### Example Usage
```bash
# Boot existing VM
./qvm-launcher.sh my_virtual_machine.qcow2

# Create new 50GB VM and install Ubuntu
./qvm-launcher.sh -f ubuntu_vm.qcow2 ubuntu-22.04-live-server-amd64.iso
```

## Configuration Details

When creating a new VM, you'll be prompted for:

1. **RAM Size**: Amount of memory in GB (default: 8GB)
2. **Storage Size**: Disk size in GB (default: 100GB)
3. **CPU Cores**: Number of CPU cores (default: 4)
   - Threads per core are **automatically detected** from your host CPU
   - No prompt for threads - the script determines this automatically

## Features Explained

### CPU Compatibility
The script uses `-cpu host` which exposes all CPU features available on your host system, ensuring optimal performance and compatibility with both AMD and Intel processors.

### Display Support
- Uses QXL display device with enhanced resources:
  - 512MB RAM for the GPU (`ram_size_mb=512`)
  - 128MB VGA memory (`vgamem_mb=128`)
  - 2048 display surfaces (`surfaces=2048`)
- These settings provide excellent resolution support for most use cases

### SPICE Integration
- Enables SPICE server for remote desktop access
- Includes SPICE agent channel for clipboard sharing
- For full clipboard functionality and optimal resolution support:
  1. Install `spice-vdagent` inside the VM:
     ```bash
     # Arch Linux
     sudo pacman -S spice-vdagent
     
     # Debian/Ubuntu
     sudo apt install spice-vdagent
     
     # Fedora
     sudo dnf install spice-vdagent
     
     # openSUSE
     sudo zypper install spice-vdagent
     ```
  2. Enable and start the service:
     ```bash
     sudo systemctl enable --now spice-vdagent.service
     ```
  3. Reconnect to the VM (restart remote-viewer or reboot the VM)

## Troubleshooting

### Black Screen Issues
If you see a black screen when connecting:
1. Ensure `spice-vdagent` is installed and running in the VM
2. Check that the VM's display settings are configured to a reasonable resolution
3. Try adjusting the resolution inside the VM's guest OS settings
4. Verify remote-viewer is up to date

### Clipboard Not Working
1. Verify `spice-vdagent` is installed and running in the VM:
   ```bash
   systemctl status spice-vdagent
   ```
2. Restart the service if needed:
   ```bash
   sudo systemctl restart spice-vdagent.service
   ```
3. Reconnect to the VM

### Performance Issues
- Ensure KVM hardware acceleration is working: `kvm-ok` or check `/dev/kvm` permissions
- Verify you're in the `kvm` group: `groups | grep kvm`
- Allocate appropriate RAM and CPU resources for your workload

## How It Works

1. **Dependency Check**: Verifies QEMU, remote-viewer, and audio system are available
2. **Configuration**: 
   - For new VMs: Prompts for RAM, storage, CPU cores (auto-detects threads)
   - For existing VMs: Uses default settings (8GB RAM, 4 cores, auto-detected threads)
3. **Disk Handling**: Creates new qcow2 disk if needed (in format mode)
4. **Audio Detection**: Automatically detects PipeWire/PulseAudio/ALSA
5. **QEMU Launch**: Boots with VirtIO storage, QXL graphics, SPICE server, and USB support
6. **SPICE Connection**: Waits for SPICE socket, then launches remote-viewer in full-screen mode
7. **Cleanup**: Properly terminates QEMU process and removes SPICE socket on exit

## License

MIT License - feel free to modify and distribute as needed.

## Contributing

Feel free to submit issues or pull requests to improve the script!

---

*Note: This script is designed for Linux host systems. Windows and macOS users may need to adapt the dependency installation steps.*