#!/bin/bash
# cleanup-common.sh - Shared cleanup functions for packer templates
#
# This file is uploaded to /tmp/cleanup-common.sh on the build VM by a
# packer file provisioner, then sourced by per-template cleanup.sh scripts.
#
# Usage in cleanup.sh:
#   source /tmp/cleanup-common.sh
#   cleanup_all  # Or call individual functions

set -e

# ============================================================================
# Shared Cleanup Functions
# ============================================================================

cleanup_grub_config() {
    # Pre-configure grub-pc to avoid interactive prompts during kernel operations
    # Without this, apt will prompt for device selection when removing kernels
    # (e.g., when lae.proxmox removes old Debian kernels after PVE install)
    if dpkg -l grub-pc >/dev/null 2>&1; then
        echo "Configuring grub-pc for non-interactive kernel operations..."
        local grub_device
        if [ -b /dev/vda ]; then
            grub_device="/dev/vda"
        elif [ -b /dev/sda ]; then
            grub_device="/dev/sda"
        else
            grub_device="/dev/vda"  # Default for cloud VMs
        fi
        echo "grub-pc grub-pc/install_devices string ${grub_device}" | debconf-set-selections
        echo "grub-pc grub-pc/install_devices_empty boolean false" | debconf-set-selections
    fi
}

cleanup_apt() {
    # Clean apt cache and lists
    echo "Cleaning apt cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*
}

cleanup_cloud_init() {
    # Reset cloud-init so it runs again on next boot
    echo "Resetting cloud-init..."
    cloud-init clean --logs

    # Remove cloud-init generated network config (will be regenerated on boot)
    rm -f /etc/netplan/50-cloud-init.yaml
}

cleanup_machine_id() {
    # Empty machine-id (will be regenerated on boot)
    # Must truncate, not delete - systemd expects the file to exist
    echo "Clearing machine-id..."
    truncate -s 0 /etc/machine-id
    truncate -s 0 /var/lib/dbus/machine-id

    # Clear hostname (cloud-init will set it)
    truncate -s 0 /etc/hostname
}

cleanup_ssh_keys() {
    # Remove SSH host keys (will be regenerated on boot)
    echo "Removing SSH host keys..."
    rm -f /etc/ssh/ssh_host_*

    # Remove build-time SSH authorized_keys (cloud-init will set at boot)
    rm -f /root/.ssh/authorized_keys
}

cleanup_shell_history() {
    # Clear shell history
    echo "Clearing shell history..."
    rm -f /root/.bash_history
    history -c 2>/dev/null || true
}

cleanup_temp_files() {
    # Clear temporary files
    echo "Clearing temporary files..."
    rm -rf /tmp/*
    rm -rf /var/tmp/*
}

cleanup_kernel_modules() {
    # Blacklist unnecessary modules for headless VMs
    echo "Blacklisting unnecessary kernel modules..."
    cat > /etc/modprobe.d/blacklist-vm.conf << 'EOF'
blacklist cfg80211
blacklist floppy
blacklist joydev
blacklist psmouse
blacklist pcspkr
EOF

    # Rebuild initramfs to apply blacklist
    update-initramfs -u
}

# ============================================================================
# Convenience Function - Run All Standard Cleanup
# ============================================================================

cleanup_all() {
    # Run all standard cleanup steps in order
    echo "Running standard cleanup..."
    cleanup_grub_config
    cleanup_apt
    cleanup_cloud_init
    cleanup_machine_id
    cleanup_ssh_keys
    cleanup_shell_history
    cleanup_temp_files
    cleanup_kernel_modules
    echo "Standard cleanup complete"
}
