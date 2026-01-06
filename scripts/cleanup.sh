#!/bin/bash
# Cleanup script for creating a reusable cloud image template

set -e

echo "Cleaning up for templating..."

# Pre-configure grub-pc to avoid interactive prompts during kernel operations
# Without this, apt will prompt for device selection when removing kernels
# (e.g., when lae.proxmox removes old Debian kernels after PVE install)
# Use /dev/vda for virtio (Proxmox/QEMU default) with /dev/sda fallback
if dpkg -l grub-pc >/dev/null 2>&1; then
    echo "Configuring grub-pc for non-interactive kernel operations..."
    if [ -b /dev/vda ]; then
        GRUB_DEVICE="/dev/vda"
    elif [ -b /dev/sda ]; then
        GRUB_DEVICE="/dev/sda"
    else
        GRUB_DEVICE="/dev/vda"  # Default for cloud VMs
    fi
    echo "grub-pc grub-pc/install_devices string ${GRUB_DEVICE}" | debconf-set-selections
    echo "grub-pc grub-pc/install_devices_empty boolean false" | debconf-set-selections
fi

# Clean apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Reset cloud-init so it runs again on next boot
cloud-init clean --logs

# Remove cloud-init generated network config (will be regenerated on boot)
rm -f /etc/netplan/50-cloud-init.yaml

# Empty machine-id (will be regenerated on boot)
# Must truncate, not delete - systemd expects the file to exist
truncate -s 0 /etc/machine-id
truncate -s 0 /var/lib/dbus/machine-id

# Clear hostname (cloud-init will set it)
truncate -s 0 /etc/hostname

# Remove SSH host keys (will be regenerated on boot)
rm -f /etc/ssh/ssh_host_*

# Remove build-time SSH authorized_keys (cloud-init will set at boot)
rm -f /root/.ssh/authorized_keys

# Clear shell history
rm -f /root/.bash_history
history -c

# Clear temporary files
rm -rf /tmp/*
rm -rf /var/tmp/*

# Blacklist unnecessary modules for headless VMs
cat > /etc/modprobe.d/blacklist-vm.conf << 'EOF'
blacklist cfg80211
blacklist floppy
blacklist joydev
blacklist psmouse
blacklist pcspkr
EOF

# Rebuild initramfs to apply blacklist
update-initramfs -u

# Zero out free space for better compression (optional, takes time)
# dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
# rm -f /EMPTY

echo "Cleanup complete"
