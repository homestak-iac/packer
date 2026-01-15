#!/bin/bash
# cleanup.sh - Cleanup script for PVE-ready Debian 13 image
#
# Sources common functions and adds PVE-specific cleanup steps.

set -e

# Source common cleanup functions
source "${BASH_SOURCE%/*}/../../shared/scripts/cleanup-common.sh"

echo "=== Debian 13 PVE Image Cleanup ==="

# ============================================================================
# PVE-Specific Cleanup (before standard cleanup)
# ============================================================================

# Remove PVE enterprise repo (requires subscription, we use no-subscription)
# This file is installed by proxmox-ve package
echo "Removing PVE enterprise repository..."
rm -f /etc/apt/sources.list.d/pve-enterprise.sources

# Remove temporary install repo (ansible will add no-subscription repo)
echo "Removing temporary PVE install repository..."
rm -f /etc/apt/sources.list.d/pve-install-repo.sources

# PVE/ifupdown2 regenerates /etc/network/interfaces during shutdown,
# so we can't reliably modify it here. Instead, add a cloud-init bootcmd
# that ensures the source directive is present and brings up eth0.
echo "Adding cloud-init bootcmd to fix network config..."
mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99-fix-network-interfaces.cfg << 'EOF'
# Ensure /etc/network/interfaces sources the .d directory and bring up eth0
# This is needed because PVE regenerates the file without the source directive
bootcmd:
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

# Keep Debian kernel as default - ansible will switch to PVE kernel
# This allows for flexibility in the deployment process

# ============================================================================
# Standard Cleanup (common steps)
# ============================================================================

cleanup_all

echo "=== Debian 13 PVE cleanup complete ==="
