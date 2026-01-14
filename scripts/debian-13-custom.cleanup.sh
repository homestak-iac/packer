#!/bin/bash
# debian-13-custom.cleanup.sh - Cleanup script for Debian 13 custom image
#
# Sources common functions and runs standard cleanup.
# Add Debian 13 specific cleanup steps here if needed.

set -e

# Source common cleanup functions
source "${BASH_SOURCE%/*}/cleanup-common.sh"

echo "=== Debian 13 Custom Image Cleanup ==="

# Run standard cleanup (all common steps)
cleanup_all

# ============================================================================
# Debian 13 Specific Cleanup (add customizations below)
# ============================================================================

# Currently no Debian 13 specific cleanup needed
# Add version-specific steps here as needed

echo "=== Debian 13 cleanup complete ==="
