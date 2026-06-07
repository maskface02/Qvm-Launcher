#!/bin/bash
#
# QVM Launcher (SDL) - QEMU Virtual Machine Launcher
# Simple, minimal, smooth — uses GTK + QXL for native window performance.
# Display manager safe: no host GL context, so LightDM/SDDM/GDM all start cleanly.
# Recommended guest resolution: 1920x1080 (set inside the VM).
#
# ─────────────────────────────────────────────────────────────────────────────
# Super/Windows key: works like remote-viewer (forwarded to guest when focused).
# Why: QEMU GTK is a local window, so the WM's global Super binding triggers
# first. We use xdotool to grab the keyboard when the VM is focused, so Super
# is forwarded to the guest. This mimics remote-viewer's SPICE behavior.
# Disable the workaround by exporting: QVM_SUPER_FIX=0
# ─────────────────────────────────────────────────────────────────────────────
#

# ── Defaults (override with env vars) ───────────────────────────────────────
#   VM_RAM         RAM in MB          (default: 8192)
#   VM_CORES       CPU cores          (default: 4)
#   VM_STORAGE     Disk size in GB    (default: 100)
#   VM_GEOMETRY    Window WxH         (default: host screen size)
#   QVM_SUPER_FIX  1 or 0             (default: 1)
RAM=${VM_RAM:-8192}
CORES=${VM_CORES:-4}
STORAGE=${VM_STORAGE:-100}
QVM_SUPER_FIX=${QVM_SUPER_FIX:-1}

# ── Host threads per core ────────────────────────────────────────────────────
get_host_threads_per_core() {
    if command -v lscpu &>/dev/null; then
        local t
        t=$(lscpu | awk '/Thread\(s\) per core:/{print $NF}')
        [[ "$t" =~ ^[0-9]+$ ]] && { echo "$t"; return; }
    fi
    if [ -r /proc/cpuinfo ]; then
        local total cores
        total=$(grep -c '^processor' /proc/cpuinfo)
        cores=$(grep '^core id' /proc/cpuinfo | sort -u | wc -l)
        [ "$cores" -gt 0 ] && echo $((total / cores)) && return
    fi
    echo 2
}
THREADS=$(get_host_threads_per_core)

# ── Audio backend detection ──────────────────────────────────────────────────
if pactl info &>/dev/null; then
    AUDIODEV="pa"
elif aplay -l &>/dev/null; then
    AUDIODEV="alsa"
else
    AUDIODEV="none"
fi

# ── Help ────────────────────────────────────────────────────────────────────
show_help() {
    cat <<EOF
Usage:
  $0 <vm-name>
      Boot existing VM (./<vm-name>/<vm-name>.qcow2)

  $0 -f <vm-name> <installer.iso>
      Create disk if needed and boot installer ISO

Window keys (GTK):
  Ctrl+Alt+F    Toggle fullscreen
  Ctrl+Alt+G    Release keyboard/mouse grab
  Ctrl+Alt+Q    Quit QEMU

Super/Windows key:
  When the VM is running, the host WM's global Super binding (e.g. GNOME
  Activities, KDE App Menu) is temporarily disabled. Super key is then
  delivered to the focused window — your QEMU VM — like remote-viewer.

  This is achieved by:
    - Wayland: gsettings (GNOME/Mutter) or kwriteconfig (KDE) to suppress
      the compositor's overlay-key binding. This is the actual fix on
      Wayland, where X11 keyboard grabs cannot affect the compositor.
    - X11:    XGrabKeyboard + XTest forwarding via the python helper
      qvm-keyboard-grab.py. Belt-and-suspenders with the gsettings fix.

  Set QVM_SUPER_FIX=0 to disable this behavior.

Env vars:
  VM_RAM         RAM in MB          (default: 8192)
  VM_CORES       CPU cores          (default: 4)
  VM_STORAGE     Disk size in GB    (default: 100)
  VM_GEOMETRY    Window WxH         (default: host screen size)
  QVM_SUPER_FIX  1 or 0             (default: 1)

Examples:
  $0 arch
  $0 -f kali kali-linux-2026.1-installer-amd64.iso
  VM_RAM=16384 VM_CORES=8 $0 cachy
  VM_GEOMETRY=1280x720 $0 cachy    # force a specific window size
EOF
    exit 1
}

# ── Args ────────────────────────────────────────────────────────────────────
FORMAT_MODE=false
VM_NAME=""
ISO=""
IMG=""

case "$1" in
    -f|--format)
        FORMAT_MODE=true
        VM_NAME="$2"
        ISO="$(realpath "$3" 2>/dev/null)"
        [ -z "$VM_NAME" ] || [ -z "$ISO" ] && show_help
        [ ! -f "$ISO" ] && { echo "Error: ISO not found: $ISO"; exit 1; }
        mkdir -p "./${VM_NAME}"
        IMG="./${VM_NAME}/${VM_NAME}.qcow2"
        ;;
    -h|--help|--help|"")
        show_help
        ;;
    *)
        VM_NAME="$1"
        IMG="./${VM_NAME}/${VM_NAME}.qcow2"
        [ ! -f "$IMG" ] && { echo "Error: VM disk not found: $IMG"; exit 1; }
        ;;
esac

# ── Dependency check ────────────────────────────────────────────────────────
for cmd in qemu-system-x86_64 qemu-img; do
    command -v "$cmd" &>/dev/null || {
        echo "Error: '$cmd' not found. Install qemu-system-x86 and qemu-utils."
        exit 1
    }
done

# Required tools for the Super key fix
MISSING_TOOLS=()
command -v gsettings &>/dev/null || MISSING_TOOLS+=("gsettings (libglib2.0-bin)")
command -v gdbus     &>/dev/null || MISSING_TOOLS+=("gdbus     (libglib2.0-bin)")
# xdotool is optional — only needed for window auto-focus. The gsettings
# fix and window resize still work without it.
command -v xdotool   &>/dev/null || echo "Note: xdotool not installed. Window auto-focus skipped; click the VM window to focus."

if [ "$QVM_SUPER_FIX" = "1" ] && [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo "Warning: missing tools for Super key fix: ${MISSING_TOOLS[*]}"
    echo "  Install: sudo apt install libglib2.0-bin"
    echo "           sudo pacman -S glib2"
    echo ""
    echo "  Falling back to gsettings-only fix (still works on Wayland GNOME)."
fi

# Required for window auto-resize (fits QEMU window to host screen)
if ! python3 -c "import Xlib" 2>/dev/null; then
    echo "Warning: python-xlib not installed. Auto-resize of VM window"
    echo "         disabled — install with: pip3 install --user python-xlib"
    echo "         For now: drag the window corner to resize to fit your screen."
fi

# ── Cleanup ─────────────────────────────────────────────────────────────────
cleanup() {
    [ -n "$GRAB_PID" ] && kill "$GRAB_PID" 2>/dev/null
    [ -n "$QEMU_PID" ] && kill "$QEMU_PID" 2>/dev/null
    restore_wm_super
    restore_kde_super
    wait 2>/dev/null
}
trap cleanup EXIT INT TERM

# ── Super key fix: WM binding suppression + keyboard grab ───────────────────
# Two complementary approaches, chosen based on session type:
#
# Wayland (most reliable): disable ALL compositor Super bindings via
#   gsettings (GNOME/Mutter) or kwriteconfig (KDE), then force Mutter
#   to reload via DBus. Keys then go to the focused window.
#
# X11 (fallback): use XGrabKeyboard + XTest forwarding via Python helper.
#   This bypasses the WM's global Super binding.
#
# Result: Super key reaches the guest in both windowed and fullscreen modes.

# Detect the user's actual DBUS session, since this script may run from
# a context (sudo, systemd, .desktop file) that lacks DBUS_SESSION_BUS_ADDRESS.
detect_user_dbus() {
    # If we already have a session bus, verify it works
    if [ -n "$DBUS_SESSION_BUS_ADDRESS" ] && \
       DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
       gsettings get org.gnome.mutter overlay-key &>/dev/null; then
        return 0
    fi

    # Try to find the user's session bus from a running process
    local uid; uid=$(id -u)
    for proc in $(pgrep -u "$uid" -x gnome-session 2>/dev/null) \
                $(pgrep -u "$uid" -x gnome-shell     2>/dev/null) \
                $(pgrep -u "$uid" -x cinnamon-session 2>/dev/null) \
                $(pgrep -u "$uid" -x plasmashell      2>/dev/null) \
                $(pgrep -u "$uid" -x kwin_x11         2>/dev/null) \
                $(pgrep -u "$uid" -x kwin_wayland     2>/dev/null); do
        local addr
        addr=$(tr '\0' '\n' < "/proc/$proc/environ" 2>/dev/null \
               | grep '^DBUS_SESSION_BUS_ADDRESS=' | head -1)
        if [ -n "$addr" ]; then
            export DBUS_SESSION_BUS_ADDRESS="${addr#DBUS_SESSION_BUS_ADDRESS=}"
            return 0
        fi
    done
    return 1
}

# Find all gsettings keys whose value contains "Super" / "<Super>" / "super"
# and save their original values, then disable them.
disable_wm_super() {
    local saved_file="/tmp/qvm-super-orig.${USER:-$(id -u)}"
    : > "$saved_file"

    # Make sure gsettings targets the right session
    detect_user_dbus || {
        echo "Super key fix: no DBUS session found, cannot use gsettings"
        return 1
    }

    # Schemas to scan
    local schemas=(
        "org.gnome.mutter"
        "org.gnome.mutter.keybindings"
        "org.gnome.shell.keybindings"
        "org.gnome.desktop.wm.keybindings"
    )

    local count=0
    for schema in "${schemas[@]}"; do
        # Get all keys in this schema
        local keys
        keys=$(gsettings list-keys "$schema" 2>/dev/null) || continue

        while IFS= read -r key; do
            [ -z "$key" ] && continue
            local val
            val=$(gsettings get "$schema" "$key" 2>/dev/null) || continue
            # Skip empty/non-string/array values
            [ -z "$val" ] && continue
            # Only touch values that contain "Super" (case-insensitive)
            echo "$val" | grep -qi "super" || continue
            # Skip values that are already empty
            case "$val" in
                "''"|'@as []'|'[]'|"@as []") continue ;;
            esac

            # Save original
            echo "$schema|$key|$val" >> "$saved_file"
            count=$((count + 1))

            # Disable: for string, set to '' ; for array, set to []
            case "$val" in
                \'*\') gsettings set "$schema" "$key" '' 2>/dev/null ;;
                \[*\]) gsettings set "$schema" "$key" '@as []' 2>/dev/null ;;
            esac
        done <<< "$keys"
    done

    # Force Mutter/GNOME Shell to reload keybindings. dconf/GSettings
    # normally notifies the shell automatically, but we kick it to be sure.
    if [ "$count" -gt 0 ] && command -v gdbus &>/dev/null; then
        # repick_keyboard re-evaluates the keyboard state
        gdbus call --session --dest org.gnome.Shell \
            --object-path /org/gnome/Shell \
            --method org.gnome.Shell.Eval \
            "global.display.repick_keyboard(); null;" 2>/dev/null
    fi

    # Verify the overlay-key actually changed (it was the primary one we
    # were trying to disable). This catches session-detection bugs.
    if [ "$count" -gt 0 ]; then
        local new_overlay
        new_overlay=$(gsettings get org.gnome.mutter overlay-key 2>/dev/null)
        if [ "$new_overlay" = "''" ]; then
            echo "Super key fix: disabled $count GNOME keybinding(s) containing Super"
            echo "  (verified: overlay-key is now empty, will be restored on exit)"
        else
            echo "Super key fix: WARNING — overlay-key is still $new_overlay"
            echo "  The gsettings change may not have reached the compositor."
        fi
    fi
    return 0
}

restore_wm_super() {
    local saved_file="/tmp/qvm-super-orig.${USER:-$(id -u)}"
    [ -f "$saved_file" ] || return 0

    detect_user_dbus || return 1

    local count=0
    while IFS='|' read -r schema key val; do
        [ -z "$schema" ] && continue
        # The saved $val is a gsettings-format value (e.g. 'Super_L' or
        # ['<Super>a']). Pass it back to gsettings set as-is.
        if gsettings set "$schema" "$key" "$val" 2>/dev/null; then
            count=$((count + 1))
        fi
    done < "$saved_file"

    # Force Mutter to reload again
    if [ "$count" -gt 0 ] && command -v gdbus &>/dev/null; then
        gdbus call --session --dest org.gnome.Shell \
            --object-path /org/gnome/Shell \
            --method org.gnome.Shell.Eval \
            "global.display.repick_keyboard(); null;" 2>/dev/null
    fi

    rm -f "$saved_file"
    if [ "$count" -gt 0 ]; then
        echo "Super key fix: restored $count GNOME keybinding(s)"
    fi
}

# KDE support: simpler, only one binding to worry about
disable_kde_super() {
    if ! command -v kwriteconfig5 &>/dev/null; then
        return 1
    fi
    local orig
    orig=$(kreadconfig5 --file kwinrc --group ModifierOnlyShortcuts --key Meta 2>/dev/null)
    if [ -n "$orig" ]; then
        local saved_file="/tmp/qvm-super-orig-kde.${USER:-$(id -u)}"
        echo "$orig" > "$saved_file"
        kwriteconfig5 --file kwinrc --group ModifierOnlyShortcuts --key Meta "none" 2>/dev/null
        command -v qdbus5 &>/dev/null && qdbus5  org.kde.KWin /KWin reconfigure 2>/dev/null
        command -v qdbus  &>/dev/null && qdbus   org.kde.KWin /KWin reconfigure 2>/dev/null
        echo "Super key fix: disabled KDE Meta shortcut (was $orig)"
        return 0
    fi
    return 1
}

restore_kde_super() {
    local f="/tmp/qvm-super-orig-kde.${USER:-$(id -u)}"
    [ -f "$f" ] || return 0
    if command -v kwriteconfig5 &>/dev/null; then
        kwriteconfig5 --file kwinrc --group ModifierOnlyShortcuts \
            --key Meta "$(cat "$f")" 2>/dev/null
        command -v qdbus5 &>/dev/null && qdbus5 org.kde.KWin /KWin reconfigure 2>/dev/null
        command -v qdbus  &>/dev/null && qdbus  org.kde.KWin /KWin reconfigure 2>/dev/null
    fi
    rm -f "$f"
    echo "Super key fix: restored KDE Meta shortcut"
}

start_super_fix() {
    # Try GNOME/Mutter first (the most common Wayland DE)
    if command -v gsettings &>/dev/null && \
       gsettings list-schemas 2>/dev/null | grep -q "org.gnome.mutter"; then
        disable_wm_super
    elif ! disable_kde_super; then
        echo "Super key fix: no supported DE detected (need GNOME or KDE)"
    fi

    # On X11, also run the keyboard grabber for extra reliability.
    if [ "${XDG_SESSION_TYPE:-x11}" = "x11" ]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local grab_script="$script_dir/qvm-keyboard-grab.py"

        if [ -f "$grab_script" ] && python3 -c "import Xlib" 2>/dev/null; then
            python3 "$grab_script" "$VM_NAME" &
            GRAB_PID=$!
        else
            [ ! -f "$grab_script" ] && echo "Note: $grab_script not found"
            python3 -c "import Xlib" 2>/dev/null || \
                echo "Note: install python-xlib for X11 keyboard grab fallback"
        fi
    fi
}

# ── Disk setup ──────────────────────────────────────────────────────────────
if [ "$FORMAT_MODE" = true ] && [ ! -f "$IMG" ]; then
    echo "Creating qcow2 disk: $IMG (${STORAGE}G)"
    qemu-img create -f qcow2 "$IMG" ${STORAGE}G
fi

# ── QEMU command ────────────────────────────────────────────────────────────
QEMU_CMD=(
    qemu-system-x86_64
    -enable-kvm
    -machine q35,accel=kvm,kernel_irqchip=on
    -m "$RAM"
    -cpu host
    -smp sockets=1,cores=$CORES,threads=$THREADS,maxcpus=$((CORES * THREADS))

    -object iothread,id=iothread0

    # GTK display — proper WM integration, window decorations, reliable
    # key capture. The window is identified by title for the Super fix.
    #
    # Note: no gl=on — the host does NOT create an OpenGL context. This
    # avoids a known conflict with the guest's 3D renderer that breaks
    # display managers (LightDM, GDM, SDDM) in some distros, particularly
    # CachyOS and other bleeding-edge Arch-based guests.
    #
    # Video device: QXL (2D paravirtualized). Chosen over virtio-vga-gl
    # because it works WITHOUT OpenGL (virtio-vga-gl requires gl=on and
    # is what caused the DM breakage). QXL is what SPICE uses for 2D,
    # is well-tested with all display managers, and provides good 2D
    # performance. No 3D acceleration in the guest, but the desktop,
    # video playback, and all display managers work correctly.
    -name "QVM - ${VM_NAME}"
    -display gtk
    # QXL: 2D paravirtualized, no GL required (DM-safe). max_outputs=1
    # for a single-display setup. vgamem_mb=64 supports up to ~4K.
    # The guest picks its own resolution — typically 1024x768 by default
    # in CachyOS. Set the guest to your target resolution (1920x1080)
    # via xrandr, display settings, or a kernel cmdline video= parameter.
    -device qxl-vga,ram_size_mb=256,vgamem_mb=64,max_outputs=1

    # USB
    -device qemu-xhci

    # Absolute mouse (can leave VM freely)
    -device virtio-tablet-pci

    # Clock sync
    -rtc base=localtime,clock=host

    # Disk
    -drive file="$IMG",format=qcow2,if=none,id=drive0,cache=none,aio=io_uring,discard=unmap
    -device virtio-blk-pci,drive=drive0,iothread=iothread0
)

# Audio (optional)
if [ "$AUDIODEV" != "none" ]; then
    QEMU_CMD+=(
        -audiodev "${AUDIODEV}",id=audio0
        -device ich9-intel-hda
        -device hda-output,audiodev=audio0
    )
fi

# Install mode
if [ "$FORMAT_MODE" = true ]; then
    QEMU_CMD+=( -cdrom "$ISO" -boot d )
fi

echo "VM: $VM_NAME  |  RAM: $((RAM/1024))GB  |  CPU: ${CORES}c/${THREADS}t  |  Audio: $AUDIODEV"
echo "QEMU display: GTK + QXL (2D paravirtualized, DM-safe)"
[ "$QVM_SUPER_FIX" = "1" ] && echo "Super key fix: enabled (forwards Super to guest when focused)"
echo ""

# ── Launch ──────────────────────────────────────────────────────────────────
# Start Super key fix FIRST so the gsettings change is in effect before
# the VM even appears. The grabber (X11 only) is also started here.
[ "$QVM_SUPER_FIX" = "1" ] && start_super_fix

"${QEMU_CMD[@]}" &
QEMU_PID=$!

# Auto-focus the QEMU window. On Wayland, focus is strict — if the user
# presses Super while the launching terminal is still focused, the key
# would go to the terminal instead of the VM. This ensures the VM has
# focus from the start.
focus_and_resize_window() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # --- Focus the VM window ---
    if command -v xdotool &>/dev/null; then
        local win_id=""
        for _ in $(seq 1 20); do
            win_id=$(xdotool search --name "QVM - ${VM_NAME}" 2>/dev/null | head -1)
            if [ -n "$win_id" ]; then
                xdotool windowactivate "$win_id" 2>/dev/null
                xdotool windowraise    "$win_id" 2>/dev/null
                echo "VM window focused — Super key will reach the guest"
                break
            fi
            sleep 0.5
        done
    fi

    # --- Resize the VM window to fit the host screen ---
    # Uses python-xlib via qvm-resize-window.py. Works on X11 and XWayland
    # (Wayland) without requiring xdotool.
    local resize_script="$script_dir/qvm-resize-window.py"
    if [ -f "$resize_script" ] && python3 -c "import Xlib" 2>/dev/null; then
        sleep 1
        python3 "$resize_script" "$VM_NAME" "${VM_GEOMETRY:-}"
    fi
}

focus_and_resize_window

wait "$QEMU_PID"
