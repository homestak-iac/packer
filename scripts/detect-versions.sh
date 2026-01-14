#!/bin/bash
# detect-versions.sh - Detect Debian and PVE versions for image naming
#
# Outputs version info in key=value format to both stdout and /tmp/image-version.txt
# The file is downloaded by packer for use in image naming.

set -e

VERSION_FILE="/tmp/image-version.txt"

# Get Debian version from /etc/os-release
get_debian_version() {
    if [[ -f /etc/os-release ]]; then
        # VERSION_ID contains the major version (e.g., "12", "13")
        local major
        major=$(grep '^VERSION_ID=' /etc/os-release | cut -d'"' -f2)

        # For minor version, check /etc/debian_version (e.g., "12.8", "13.1")
        if [[ -f /etc/debian_version ]]; then
            local full_version
            full_version=$(cat /etc/debian_version)
            # Handle testing/sid which might say "trixie/sid" or similar
            if [[ "$full_version" =~ ^[0-9]+\.[0-9]+ ]]; then
                echo "$full_version"
                return
            fi
        fi

        # Fallback to major version only
        echo "$major"
    else
        echo "unknown"
    fi
}

# Get PVE version if installed
get_pve_version() {
    if command -v pveversion &>/dev/null; then
        # pveversion outputs: pve-manager/X.Y.Z/...
        local pve_full
        pve_full=$(pveversion 2>/dev/null | head -1)
        # Extract version number (e.g., "8.2.2" from "pve-manager/8.2.2/...")
        local pve_version
        pve_version=$(echo "$pve_full" | cut -d'/' -f2)
        # Return major.minor (e.g., "8.2" from "8.2.2")
        echo "$pve_version" | cut -d'.' -f1,2
    else
        echo ""
    fi
}

# Detect versions
debian_version=$(get_debian_version)
pve_version=$(get_pve_version)

# Create version file
{
    echo "DEBIAN_VERSION=$debian_version"
    echo "PVE_VERSION=$pve_version"
} > "$VERSION_FILE"

# Output to stdout for build log visibility
echo "=== Detected Versions ==="
echo "Debian: $debian_version"
if [[ -n "$pve_version" ]]; then
    echo "PVE: $pve_version"
else
    echo "PVE: not installed"
fi
echo "Version file saved to: $VERSION_FILE"
