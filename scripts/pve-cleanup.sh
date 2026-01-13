#!/bin/bash
# Cleanup script for PVE-ready cloud image template
# Extends base cleanup with PVE-specific operations

set -e

echo "Cleaning up for PVE templating..."

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

# ==========================================
# PVE-specific cleanup
# ==========================================

# Remove PVE enterprise repo (requires subscription, we use no-subscription)
# This file is installed by proxmox-ve package
echo "Removing PVE enterprise repository..."
rm -f /etc/apt/sources.list.d/pve-enterprise.sources

# Remove temporary install repo (ansible will add no-subscription repo)
echo "Removing temporary PVE install repository..."
rm -f /etc/apt/sources.list.d/pve-install-repo.sources

# PVE/ifupdown2 regenerates /etc/network/interfaces during shutdown,
# so we can't reliably modify it here. Instead, add a cloud-init runcmd
# that ensures the source directive is present and brings up eth0.
# NOTE: Using runcmd (not bootcmd) so it runs after networking is up.
echo "Adding cloud-init runcmd to fix network config..."
mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99-fix-network-interfaces.cfg << 'EOF'
# Ensure /etc/network/interfaces sources the .d directory and bring up eth0
# This is needed because PVE regenerates the file without the source directive
# Using runcmd instead of bootcmd - runs after networking, reduces boot contention
runcmd:
  - |
    if ! grep -q 'source /etc/network/interfaces.d' /etc/network/interfaces 2>/dev/null; then
      echo '' >> /etc/network/interfaces
      echo 'source /etc/network/interfaces.d/*' >> /etc/network/interfaces
    fi
  - |
    # Bring up eth0 if it exists and has no IP
    if ip link show eth0 >/dev/null 2>&1; then
      if ! ip addr show eth0 | grep -q 'inet '; then
        ip link set eth0 up
        dhclient eth0 2>/dev/null || true
      fi
    fi
EOF

# Clean up any existing cloud-init network config from build
rm -f /etc/network/interfaces.d/*

# Create marker file for ansible to detect pre-installed packages
# ansible pve-install role checks for this and skips package installation
echo "Creating pre-installed marker file..."
touch /etc/pve-packages-preinstalled

# ==========================================
# Guest agent boot optimization (packer#13)
# ==========================================
# Root cause of ~2m 15s guest agent delay:
# - PVE services + cloud-init + I/O contention at boot
# Solution (3-pronged):
# 1. Disable non-essential services that slow boot
# 2. bootcmd→runcmd (already done above)
# 3. Prioritize qemu-guest-agent.service

echo "Disabling non-essential PVE services at boot..."
# pvestatd: Stats daemon - not needed for guest agent response
# postfix: Mail server - not critical for boot
# open-iscsi: iSCSI - not used in nested PVE testing
for service in pvestatd postfix open-iscsi; do
    if systemctl list-unit-files "${service}.service" >/dev/null 2>&1; then
        systemctl disable "${service}.service" 2>/dev/null || true
        echo "  Disabled ${service}.service"
    fi
done

echo "Adding systemd drop-in to prioritize qemu-guest-agent..."
mkdir -p /etc/systemd/system/qemu-guest-agent.service.d
cat > /etc/systemd/system/qemu-guest-agent.service.d/10-priority.conf << 'EOF'
# Prioritize guest agent startup for faster IP detection
# Reduces delay from ~135s to ~30-45s in nested PVE testing
[Unit]
# Start as early as possible after networking
After=network-online.target
Wants=network-online.target

[Service]
# Nice value: -5 gives higher priority than default (0)
Nice=-5
# Start immediately, don't wait for other services
Type=simple
EOF

# Reload systemd to pick up the new drop-in
systemctl daemon-reload

# Keep Debian kernel as default - ansible will switch to PVE kernel
# This allows for flexibility in the deployment process

# ==========================================
# Base cleanup (same as cleanup.sh)
# ==========================================

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
history -c 2>/dev/null || true

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

echo "PVE cleanup complete"
