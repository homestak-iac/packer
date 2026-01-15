#!/bin/bash
# cleanup.sh - Cleanup script for Debian 12 custom image
#
# Sources common functions and runs standard cleanup.
# Add Debian 12 specific cleanup steps here if needed.

set -e

# Source common cleanup functions
source "${BASH_SOURCE%/*}/../../../shared/scripts/cleanup-common.sh"

echo "=== Debian 12 Custom Image Cleanup ==="

# Run standard cleanup (all common steps)
cleanup_all

# ============================================================================
# Debian 12 Specific Cleanup (add customizations below)
# ============================================================================

# Currently no Debian 12 specific cleanup needed
# Add version-specific steps here as needed

echo "=== Debian 12 cleanup complete ==="
