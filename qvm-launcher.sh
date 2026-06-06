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

# ── Install shell completion ─────────────────────────────────────────────────
install_completion() {
    # Determine the real user's home directory (handles sudo)
    if [ -n "$SUDO_USER" ]; then
        USER_HOME=$(eval echo ~$SUDO_USER)
    else
        USER_HOME=$HOME
    fi

    # Detect the user's shell
    SHELL_NAME=$(basename "$SHELL")
    echo "Detected shell: $SHELL_NAME"

    case "$SHELL_NAME" in
        bash)
            COMPLETION_DIR="$USER_HOME/.local/share/bash-completion/completions"
            mkdir -p "$COMPLETION_DIR"
            cp AutoCompletion/qvm-completion.bash "$COMPLETION_DIR/qvm-launcher"
            echo "Bash completion installed to: $COMPLETION_DIR/qvm-launcher"
            
            # Auto-update .bashrc if needed
            RC_FILE="$USER_HOME/.bashrc"
            if [ -f "$RC_FILE" ]; then
                if ! grep -qi "QVM Launcher completion" "$RC_FILE"; then
                    echo "" >> "$RC_FILE"
                    echo "# QVM Launcher completion" >> "$RC_FILE"
                    echo "source $COMPLETION_DIR/qvm-launcher" >> "$RC_FILE"
                    echo "Added completion to $RC_FILE"
                else
                    echo "Completion already configured in $RC_FILE"
                fi
            else
                echo "Creating $RC_FILE with completion"
                echo "# QVM Launcher completion" > "$RC_FILE"
                echo "source $COMPLETION_DIR/qvm-launcher" >> "$RC_FILE"
            fi
            ;;
        zsh)
            # Check if Oh My Zsh is installed
            if [ -d "$USER_HOME/.oh-my-zsh" ]; then
                # Use OMZ's custom completions directory (auto-added to fpath by OMZ)
                OMZ_COMPLETION_DIR="$USER_HOME/.oh-my-zsh/custom/completions"
                mkdir -p "$OMZ_COMPLETION_DIR"
                if [ -f "$OMZ_COMPLETION_DIR/_qvm-launcher" ]; then
                    echo "Completion already installed to $OMZ_COMPLETION_DIR/_qvm-launcher"
                else
                    cp AutoCompletion/qvm-completion.zsh "$OMZ_COMPLETION_DIR/_qvm-launcher"
                    echo "Zsh completion installed to: $OMZ_COMPLETION_DIR/_qvm-launcher"
                    echo "Note: Open a new terminal or run 'exec zsh' for completion to take effect."
                fi
            else
                # Non-OMZ: add to standard user completion directory
                COMPLETION_DIR="$USER_HOME/.zsh/completion"
                mkdir -p "$COMPLETION_DIR"
                cp AutoCompletion/qvm-completion.zsh "$COMPLETION_DIR/_qvm-launcher"
                echo "Zsh completion installed to: $COMPLETION_DIR/_qvm-launcher"

                # Auto-update .zshrc if needed (only fpath, compinit handled by zsh framework or user)
                RC_FILE="$USER_HOME/.zshrc"
                if [ -f "$RC_FILE" ]; then
                    if ! grep -qi "QVM Launcher completion" "$RC_FILE"; then
                        echo "" >> "$RC_FILE"
                        echo "# QVM Launcher completion" >> "$RC_FILE"
                        echo "fpath=($COMPLETION_DIR \$fpath)" >> "$RC_FILE"
                        echo "Added completion to $RC_FILE"
                    else
                        echo "Completion already configured in $RC_FILE"
                    fi
                else
                    echo "Creating $RC_FILE with completion"
                    echo "# QVM Launcher completion" > "$RC_FILE"
                    echo "fpath=($COMPLETION_DIR \$fpath)" >> "$RC_FILE"
                fi
                echo "Note: Open a new terminal or run 'exec zsh' for completion to take effect."
            fi
            ;;
        fish)
            COMPLETION_DIR="$USER_HOME/.config/fish/completions"
            mkdir -p "$COMPLETION_DIR"
            # Note: We don't have a native fish completion yet.
            # As a workaround, we can suggest using bass to use the bash completion.
            # For now, we'll copy the bash completion with a .fish extension and note it may need adaptation.
            cp AutoCompletion/qvm-completion.bash "$COMPLETION_DIR/qvm-launcher.fish"
            echo "Fish completion installed to: $COMPLETION_DIR/qvm-launcher.fish"
            echo "Note: This is a bash completion file placed in the fish completion directory."
            echo "For best results, consider using the 'bass' tool to use bash completions in fish:"
            echo "  bass source $COMPLETION_DIR/qvm-launcher.fish"
            echo "Or create a native fish completion script."
            ;;
        *)
            echo "Error: Unsupported shell  for automatic completion installation."
            echo "Supported shells: bash, zsh, fish"
            echo "You can manually install completion from qvm-completion.bash or qvm-completion.zsh"
            return 1
            ;;
    esac
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

# ── Save VM configuration ────────────────────────────────────────────────────
save_config() {
    local img_path="$1"
    local config_file="${img_path}.conf"
    
    # Save current configuration
    {
        echo "RAM=$RAM"
        echo "STORAGE=$STORAGE"
        echo "CORES=$CORES"
        echo "THREADS=$THREADS"
    } > "$config_file"
    
    echo "Configuration saved to: $config_file"
}

# ── Load VM configuration ────────────────────────────────────────────────────
load_config() {
    local img_path="$1"
    local config_file="${img_path}.conf"
    
    if [ -f "$config_file" ]; then
        # Source the config file to load variables
        # shellcheck disable=SC1090
        . "$config_file"
        echo "Loaded configuration from: $config_file"
        return 0
    else
        return 1
    fi
}

# ── List available VMs ───────────────────────────────────────────────────────
list_vms() {
    # Find all subdirectories that contain a .qcow2 file with the same name
    local vm_dirs=()
    while IFS= read -r -d '' dir; do
        if [ -f "${dir}/$(basename "${dir}").qcow2" ]; then
            vm_dirs+=("$(basename "${dir}")")
        fi
    done < <(find . -maxdepth 1 -type d ! -name ".*" ! -name ".git" -print0 2>/dev/null | sort -z)
    
    if [ ${#vm_dirs[@]} -eq 0 ]; then
        echo "No VMs found. Create one with: $0 -f <vm-name> <installer.iso>"
    else
        echo "Available VMs:"
        for vm in "${vm_dirs[@]}"; do
            echo "  - $vm"
        done
    fi
}

# ── Resolve VM name to path ─────────────────────────────────────────────────
resolve_vm_path() {
    local vm_name="$1"
    local vm_path="./${vm_name}/${vm_name}.qcow2"
    
    if [ -f "$vm_path" ]; then
        echo "$vm_path"
        return 0
    else
        return 1
    fi
}

# ── Help ─────────────────────────────────────────────────────────────────────
show_help() {
    echo "Usage:"
    echo "  $0 <vm-name>"
    echo "      Boot existing VM (searches in ./<vm-name>/<vm-name>.qcow2)"
    echo
    echo "  $0 -f <vm-name> <installer.iso>"
    echo "      Create disk if needed and boot installer ISO"
    echo
    echo "  $0 --list"
    echo "      List all available VMs"
    echo
    echo "  $0 --install-completion"
    echo "      Install shell autocompletion for bash/zsh/fish (auto-detected)"
    echo
    echo "Tab completion: After installation, tab-complete VM names in your shell"
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
VM_NAME=""
ISO=""
IMG=""

case "$1" in
    -f|--format)
        FORMAT_MODE=true
        VM_NAME="$2"
        ISO="$(realpath "$3" 2>/dev/null)"
        if [ -z "$VM_NAME" ] || [ -z "$ISO" ]; then
            echo "Error: missing VM name or ISO."
            show_help
        fi
        if [ ! -f "$ISO" ]; then
            echo "Error: ISO file not found: $ISO"
            exit 1
        fi
        # Resolve/create VM directory and set IMG path
        mkdir -p "./${VM_NAME}"
        IMG="./${VM_NAME}/${VM_NAME}.qcow2"
        ;;
    --list)
        list_vms
        exit 0
        ;;
    --install-completion)
        install_completion
        exit 0
        ;;
    --help|-h)
        show_help
        ;;
    "")
        show_help
        ;;
    *)  
        VM_NAME="$1"
        # Resolve VM name to actual path
        if IMG="$(resolve_vm_path "$VM_NAME")"; then
            # Found, continue
            :
        else
            echo "Error: VM '$VM_NAME' not found."
            list_vms
            exit 1
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
    # Save configuration for future use
    save_config "$IMG"
else
    # Try to load saved configuration for existing VM
    if load_config "$IMG"; then
        echo "=== Booting Existing VM (using saved config) ==="
        echo "  RAM: $((RAM/1024)) GB"
        echo "  Storage: Existing disk will be used"
        echo "  CPU: $CORES cores × $THREADS threads"
        echo ""
    else
        # No saved config found - ask user what to do
        echo "=== No saved configuration found for this VM ==="
        echo "Choose an option:"
        echo "  1) Boot with default settings (8GB RAM, 4 cores)"
        echo "  2) Configure custom settings for this boot"
        read -p "Enter choice (1 or 2, default: 1): " choice
        
        if [ "$choice" = "2" ]; then
            configure_vm
            # Ask if user wants to save this config for future boots
            read -p "Save this configuration for future boots? (y/N): " save_choice
            if [[ "$save_choice" =~ ^[Yy]$ ]]; then
                save_config "$IMG"
            fi
        else
            # Use default values
            DEFAULT_RAM=8192      # 8GB in MB
            DEFAULT_CORES=4
            
            RAM=$DEFAULT_RAM
            # STORAGE is ignored for existing VMs (use actual disk size)
            CORES=$DEFAULT_CORES
            
            # Determine threads per core from host (no prompt)
            THREADS=$(get_host_threads_per_core)
            
            echo "=== Booting Existing VM (using defaults) ==="
            echo "  RAM: $((RAM/1024)) GB"
            echo "  Storage: Existing disk will be used"
            echo "  CPU: $CORES cores × $THREADS threads"
            echo ""
        fi
    fi
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
    -machine q35,accel=kvm,kernel_irqchip=on
    -m $RAM
    -cpu host
    # Fixed CPU topology to avoid hyperthreading warnings on AMD
    -smp sockets=1,cores=$CORES,threads=$THREADS,maxcpus=$((CORES * THREADS))

    # I/O thread for disk operations (offloads from main thread)
    -object iothread,id=iothread0

    # QXL display — required by spice-vdagent for auto-resize
    -device qxl-vga,ram_size_mb=256,vgamem_mb=64
    -display none

    # SPICE server for display + clipboard
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

    # Absolute pointing device — lets mouse leave VM window freely
    -device virtio-tablet-pci

    # Dynamic memory management
    -device virtio-balloon-pci

    # Better guest clock sync
    -rtc base=localtime,clock=host

    -serial mon:stdio
)

if [ "$FORMAT_MODE" = true ]; then
    QEMU_CMD+=(
        -drive file="$IMG",format=qcow2,if=none,id=drive0,cache=none,aio=io_uring,discard=unmap
        -device virtio-blk-pci,drive=drive0,iothread=iothread0
        -cdrom "$ISO"
        -boot d
    )
else
    QEMU_CMD+=(
        -drive file="$IMG",format=qcow2,if=none,id=drive0,cache=none,aio=io_uring,discard=unmap
        -device virtio-blk-pci,drive=drive0,iothread=iothread0
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
echo "IMPORTANT: For clipboard copy-paste and auto-resize, install spice-vdagent in the VM:"
echo "  sudo pacman -S spice-vdagent   (Arch Linux)"
echo "  sudo systemctl enable --now spice-vdagent.service"
echo ""

remote-viewer --title "QVM - ${VM_NAME}" "spice+unix://${SPICE_SOCK}" &

RV_PID=$!

# Resize window once to target resolution (avoids --auto-resize constant redraws)
if command -v xdotool &>/dev/null; then
    sleep 2
    WIN_ID=$(xdotool search --name "QVM - ${VM_NAME}" 2>/dev/null | tail -1)
    if [ -n "$WIN_ID" ]; then
        xdotool windowsize "$WIN_ID" "${VM_GEOMETRY:-1920x1080}" 2>/dev/null
    fi
fi

wait $RV_PID

kill "${QEMU_PID}" 2>/dev/null