#!/bin/bash
# Cleanup script for creating a reusable cloud image template

set -e

echo "Cleaning up for templating..."

# Clean apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Reset cloud-init so it runs again on next boot
cloud-init clean --logs

# Remove machine-id (will be regenerated on boot)
rm -f /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Clear hostname (cloud-init will set it)
truncate -s 0 /etc/hostname

# Remove SSH host keys (will be regenerated on boot)
rm -f /etc/ssh/ssh_host_*

# Clear shell history
rm -f /root/.bash_history
history -c

# Clear temporary files
rm -rf /tmp/*
rm -rf /var/tmp/*

# Zero out free space for better compression (optional, takes time)
# dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
# rm -f /EMPTY

echo "Cleanup complete"
