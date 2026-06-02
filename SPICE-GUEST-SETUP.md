# SPICE Guest Agent Setup Guide

## Why Install SPICE Guest Agent?

The SPICE guest agent (`spice-vdagent`) enables:
- Clipboard copy-paste between host and guest
- Automatic display resolution adjustment when resizing the viewer window
- Improved mouse integration

## Installation Instructions

### Arch Linux / Manjaro / Cachy
```bash
sudo pacman -S spice-vdagent
sudo systemctl enable --now spice-vdagentd.service
```

### Ubuntu / Debian
```bash
sudo apt update
sudo apt install spice-vdagent
sudo systemctl enable --now spice-vdagent.service
```

### Fedora / RHEL / CentOS
```bash
sudo dnf install spice-vdagent
sudo systemctl enable --now spice-vdagent.service
```

### openSUSE
```bash
sudo zypper install spice-vdagent
sudo systemctl enable --now spice-vdagent.service
```

## Verification

After installation, verify the service is running:
```bash
# For Arch/Manjaro/Cachy:
systemctl status spice-vdagentd.service

# For Ubuntu/Debian/Fedora/openSUSE:
systemctl status spice-vdagent.service
```

You should see "active (running)" in the output.

## Notes

- The SPICE agent runs as a daemon inside the guest VM
- It communicates with the host-side SPICE channel set up by the qvm-launcher.sh script
- No reboot is required; the agent starts immediately after enabling the service
- For Windows guests, use the [Spice Guest Tools](https://www.spice-space.org/download.html) instead

## Troubleshooting

If clipboard copy-paste (either direction) or dynamic resizing doesn't work:

1. **Ensure the service is running**:
   ```bash
   systemctl status spice-vdagent.service
   ```
   You should see "active (running)" in the output.

2. **Check the journal for errors**:
   ```bash
   journalctl -u spice-vdagent.service --since "5 minutes ago"
   ```
   Look for any error messages related to SPICE or clipboard.

3. **Verify the SPICE connection is active**:
   Check that the QEMU command line includes the vdagent channel:
   ```bash
   ps aux | grep qemu
   ```
   You should see something like:
   `-device virtio-serialport,chardev=vdagent,name=com.redhat.spice.0`

4. **Test the clipboard channel manually**:
   In the guest VM, you can test if the vdagent is working by checking if the service can communicate with the host:
   ```bash
   # This should show the agent is connected
   systemctl status spice-vdagent.service
   ```
   Look for "Connected to SPICE server" in the journal.

5. **Test clipboard in both directions**:
   - Try copying text from the host and pasting in the guest (host→guest)
   - Try copying text from the guest and pasting in the host (guest→host)
   This helps determine if the issue is unidirectional.

6. **Try restarting the service**:
   Sometimes the service needs to be restarted after the graphical session is fully started:
   ```bash
   sudo systemctl restart spice-vdagent.service
   ```

7. **Check for missing dependencies**:
   Ensure you have dbus and X11 utilities installed:
   ```bash
   # Arch Linux
   sudo pacman -S dbus xorg-xprop
   
   # Ubuntu/Debian
   sudo apt install dbus x11-utils
   
   # Fedora
   sudo dnf install dbus xorg-x11-utils
   ```

8. **Verify clipboard manager is running** (if using one):
   Some clipboard managers can interfere. Try disabling them temporarily to test.

9. **Look for SELinux or AppArmor blocking**:
   If you're using SELinux or AppArmor, check if they're blocking the spice-vdagent process.

## Notes

- The SPICE agent runs as a daemon inside the guest VM
- It communicates with the host-side SPICE channel set up by the qvm-launcher.sh script
- No reboot is required; the agent starts immediately after enabling the service
- For Windows guests, use the [Spice Guest Tools](https://www.spice-space.org/download.html) instead
- Clipboard works in both directions (host→guest and guest→host) when the agent is properly running
- Note: Some applications (especially terminal emulators or flatpak/snap apps) may not integrate with the system clipboard. Test with a standard text editor like gedit, mousepad, or Notepad (if using Windows).