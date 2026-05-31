#!/bin/bash
#
# QVM Launcher - QEMU Virtual Machine Launcher
# Interactive configuration for RAM, storage, and CPU
# Works with both AMD and Intel processors
#

# ── Detect host audio backend ─────────────────────────────────────────────────
detect_audio() {
    if pactl info 2>/dev/null | grep -qi "pipewire"; then
        echo "pipewire"
    elif pactl info &>/dev/null; then
        echo "pa"
    elif aplay -l &>/dev/null; then
        echo "alsa"
    else
        echo "none"
    fi
}

# ── Detect host threads per core ─────────────────────────────────────────────
get_host_threads_per_core() {
    local threads_per_core=2  # default
    
    # Try lscpu first
    if command -v lscpu &>/dev/null; then
        threads_per_core=$(lscpu | grep -i 'Thread(s) per core:' | awk '{print $NF}')
        # Ensure it's a number
        if [[ "$threads_per_core" =~ ^[0-9]+$ ]]; then
            echo "$threads_per_core"
            return
        fi
    fi
    
    # Fallback to /proc/cpuinfo
    if [ -r /proc/cpuinfo ]; then
        local total_threads cores
        total_threads=$(grep -c '^processor' /proc/cpuinfo)
        # Count unique core IDs
        cores=$(grep '^core id' /proc/cpuinfo | sort -u | wc -l)
        if [ "$cores" -gt 0 ]; then
            threads_per_core=$((total_threads / cores))
        else
            # If we can't determine cores, assume 1 core with all threads
            threads_per_core=$total_threads
        fi
        # Ensure it's at least 1
        [ "$threads_per_core" -lt 1 ] && threads_per_core=1
        echo "$threads_per_core"
        return
    fi
    
    # Final fallback
    echo "$threads_per_core"
}

# ── Help ─────────────────────────────────────────────────────────────────────
show_help() {
    echo "Usage:"
    echo "  $0 <vm.qcow2>"
    echo "      Boot existing VM"
    echo
    echo "  $0 -f <vm.qcow2> <installer.iso>"
    echo "      Create disk if needed and boot installer ISO"
    exit 1
}

# ── Interactive Configuration ────────────────────────────────────────────────
configure_vm() {
    # Default values
    DEFAULT_RAM=8192      # 8GB in MB
    DEFAULT_STORAGE=100   # 100GB
    DEFAULT_CORES=4
    
    echo "=== VM Configuration ==="
    
    # RAM configuration
    read -p "RAM size in GB (default: ${DEFAULT_RAM/1024/}): " ram_input
    if [[ -z "$ram_input" ]]; then
        RAM=$DEFAULT_RAM
    else
        # Validate input is a positive number
        if ! [[ "$ram_input" =~ ^[0-9]+$ ]]; then
            echo "Invalid input. Using default RAM: ${DEFAULT_RAM/1024/}GB"
            RAM=$DEFAULT_RAM
        else
            RAM=$((ram_input * 1024))  # Convert GB to MB
            if [[ $RAM -lt 512 ]]; then
                echo "RAM too low. Using minimum 512MB"
                RAM=512
            fi
        fi
    fi
    
    # Storage configuration
    read -p "Storage size in GB (default: $DEFAULT_STORAGE): " storage_input
    if [[ -z "$storage_input" ]]; then
        STORAGE=$DEFAULT_STORAGE
    else
        # Validate input is a positive number
        if ! [[ "$storage_input" =~ ^[0-9]+$ ]]; then
            echo "Invalid input. Using default storage: $DEFAULT_STORAGE GB"
            STORAGE=$DEFAULT_STORAGE
        else
            STORAGE=$storage_input
            if [[ $STORAGE -lt 10 ]]; then
                echo "Storage too small. Using minimum 10GB"
                STORAGE=10
            fi
        fi
    fi
    
    # CPU cores configuration
    read -p "Number of CPU cores (default: $DEFAULT_CORES): " cores_input
    if [[ -z "$cores_input" ]]; then
        CORES=$DEFAULT_CORES
    else
        # Validate input is a positive number
        if ! [[ "$cores_input" =~ ^[0-9]+$ ]]; then
            echo "Invalid input. Using default cores: $DEFAULT_CORES"
            CORES=$DEFAULT_CORES
        else
            CORES=$cores_input
            if [[ $CORES -lt 1 ]]; then
                echo "Core count too low. Using minimum 1 core"
                CORES=1
            fi
        fi
    fi
    
    # Determine threads per core from host (no prompt)
    THREADS=$(get_host_threads_per_core)
    
    echo ""
    echo "Configuration summary:"
    echo "  RAM: $((RAM/1024)) GB"
    echo "  Storage: $STORAGE GB"
    echo "  CPU: $CORES cores × $THREADS threads"
    echo ""
}

# ── Args ─────────────────────────────────────────────────────────────────────
FORMAT_MODE=false
IMG=""
ISO=""

case "$1" in
    -f|--format)
        FORMAT_MODE=true
        IMG="$(realpath "$2" 2>/dev/null)"
        ISO="$(realpath "$3" 2>/dev/null)"
        if [ -z "$IMG" ] || [ -z "$ISO" ]; then
            echo "Error: missing VM image or ISO."
            show_help
        fi
        if [ ! -f "$ISO" ]; then
            echo "Error: ISO file not found: $ISO"
            exit 1
        fi
        ;;
    --help|-h)
        show_help
        ;;
    "")
        show_help
        ;;
    *)  
        IMG="$(realpath "$1" 2>/dev/null)"
        if [ -z "$IMG" ]; then
            echo "Error: invalid path: $1"
            show_help
        fi
        ;;
esac

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check for QEMU
    if ! command -v qemu-system-x86_64 &>/dev/null; then
        missing_deps+=("qemu-system-x86_64")
    fi
    
    if ! command -v qemu-img &>/dev/null; then
        missing_deps+=("qemu-img")
    fi
    
    # Check for remote-viewer (SPICE client)
    if ! command -v remote-viewer &>/dev/null; then
        missing_deps+=("remote-viewer")
    fi
    
    # Check for audio systems (at least one should be present)
    if ! command -v pactl &>/dev/null && ! command -v aplay &>/dev/null; then
        missing_deps+=("pulseaudio or alsa-utils")
    fi
    
    if [ ${#missing_deps[@]} -eq 0 ]; then
        return 0  # All dependencies present
    fi
    
    echo "Error: Missing required dependencies:"
    for dep in "${missing_deps[@]}"; do
        echo "  - $dep"
    done
    echo ""
    
    # Provide installation guidance
    echo "To install missing dependencies:"
    echo ""
    
    # Detect distribution for specific guidance
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                echo "  On Debian/Ubuntu:"
                echo "    sudo apt update"
                echo "    sudo apt install -y qemu-system-x86 qemu-utils virt-viewer"
                ;;
            arch|manjaro)
                echo "  On Arch Linux/Manjaro:"
                echo "    sudo pacman -Sy --needed qemu virt-viewer"
                ;;
            fedora|rhel|centos)
                echo "  On Fedora/RHEL/CentOS:"
                echo "    sudo dnf install -y @virtualization virt-viewer"
                ;;
            opensuse*|sles*)
                echo "  On openSUSE/SLES:"
                echo "    sudo zypper install -y qemu-x86 virt-viewer"
                ;;
            *)
                echo "  On your distribution, install:"
                echo "    - QEMU system emulator (qemu-system-x86_64)"
                echo "    - QEMU disk image utility (qemu-img)"
                echo "    - SPICE client (remote-viewer, usually in virt-viewer package)"
                echo "    - Audio system (pulseaudio, alsa-utils, or pipewire)"
                ;;
        esac
    else
        echo "  Please install:"
        echo "    - QEMU system emulator (qemu-system-x86_64)"
        echo "    - QEMU disk image utility (qemu-img)"
        echo "    - SPICE client (remote-viewer, usually in virt-viewer package)"
        echo "    - Audio system (pulseaudio, alsa-utils, or pipewire)"
    fi
    
    echo ""
    echo "Note: For hardware acceleration without sudo, you may need to:"
    echo "  1. Add your user to the 'kvm' or 'libvirt' group:"
    echo "     sudo adduser \$USER kvm"
    echo "  2. Log out and log back in for group changes to take effect"
    echo ""
    
    return 1
}

if ! check_dependencies; then
    exit 1
fi

# Get VM configuration - only prompt when creating/installing new VM
if [ "$FORMAT_MODE" = true ]; then
    configure_vm
else
    # Use default values when booting existing VM (no prompting)
    DEFAULT_RAM=8192      # 8GB in MB
    DEFAULT_STORAGE=100   # 100GB (not used for existing VM but set for consistency)
    DEFAULT_CORES=4
    
    RAM=$DEFAULT_RAM
    STORAGE=$DEFAULT_STORAGE
    CORES=$DEFAULT_CORES
    
    # Determine threads per core from host (no prompt)
    THREADS=$(get_host_threads_per_core)
    
    echo "=== Booting Existing VM (using defaults) ==="
    echo "  RAM: $((RAM/1024)) GB"
  echo "  Storage: Existing disk will be used"
    echo "  CPU: $CORES cores × $THREADS threads"
    echo ""
fi

# ── Disk setup ───────────────────────────────────────────────────────────────
if [ "$FORMAT_MODE" = true ]; then
    if [ ! -f "$IMG" ]; then
        echo "Creating qcow2 disk: $IMG (${STORAGE}G)"
        qemu-img create -f qcow2 "$IMG" ${STORAGE}G
    else
        echo "Using existing disk: $IMG"
    fi
fi

if [ "$FORMAT_MODE" = false ] && [ ! -f "$IMG" ]; then
    echo "Error: VM disk does not exist: $IMG"
    exit 1
fi

# ── Audio / SPICE socket ──────────────────────────────────────────────────────
AUDIODEV=$(detect_audio)
SPICE_SOCK="/tmp/spice-$$.sock"
echo "Audio backend: ${AUDIODEV}"

cleanup() {
    kill "${QEMU_PID}" 2>/dev/null
    rm -f "${SPICE_SOCK}"
}
trap cleanup EXIT

# ── QEMU command ─────────────────────────────────────────────────────────────
QEMU_CMD=(
    qemu-system-x86_64
    -enable-kvm
    -m $RAM
    -cpu host
    # Fixed CPU topology to avoid hyperthreading warnings on AMD
    -smp sockets=1,cores=$CORES,threads=$THREADS,maxcpus=$((CORES * THREADS))

    # QXL display device optimized for high resolution SPICE support
    -device qxl-vga,ram_size_mb=512,vgamem_mb=128,surfaces=2048
    -display none

    # SPICE agent for clipboard and better resolution support
    -spice unix=on,addr="${SPICE_SOCK}",disable-ticketing=on

    # vdagent clipboard channel
    -device virtio-serial
    -chardev spicevmc,id=vdagent,name=vdagent
    -device virtserialport,chardev=vdagent,name=com.redhat.spice.0

    # Audio
    -audiodev "${AUDIODEV}",id=audio0
    -device ich9-intel-hda
    -device hda-output,audiodev=audio0

    # USB
    -device qemu-xhci

    -serial mon:stdio
)

if [ "$FORMAT_MODE" = true ]; then
    QEMU_CMD+=(
        -drive file="$IMG",format=qcow2,if=virtio
        -cdrom "$ISO"
        -boot d
    )
else
    QEMU_CMD+=(
        -drive file="$IMG",format=qcow2,if=virtio
    )
fi

# Show the QEMU command for debugging
echo "QEMU command: ${QEMU_CMD[@]}"
echo ""

# ── Launch ───────────────────────────────────────────────────────────────────
"${QEMU_CMD[@]}" &
QEMU_PID=$!

echo "Waiting for SPICE socket..."
for i in $(seq 1 20); do
    [ -S "$SPICE_SOCK" ] && break
    sleep 0.5
done

if [ ! -S "$SPICE_SOCK" ]; then
    echo "Error: SPICE socket never appeared — QEMU may have crashed"
    exit 1
fi

echo "VM running (PID: ${QEMU_PID}) — opening remote-viewer..."
echo ""
echo "IMPORTANT: For clipboard copy-paste and optimal resolution support, please install the spice-vdagent package inside the VM and start the service."
echo "In the VM, you can run:"
echo "  sudo pacman -S spice-vdagent   (for Arch Linux)"
echo "  sudo systemctl enable --now spice-vdagent.service"
echo ""

# remote-viewer is now the main window — script blocks here until it closes
remote-viewer --full-screen "spice+unix://${SPICE_SOCK}"

# remote-viewer closed — shut down QEMU too
kill "${QEMU_PID}" 2>/dev/null