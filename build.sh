#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# SSH key handling - generates ephemeral keypair or uses existing key
# Usage: SSH_KEY_FILE=~/.ssh/id_rsa ./build.sh  (use existing key)
#        ./build.sh                              (generate ephemeral key)
SSH_KEY_FILE="${SSH_KEY_FILE:-ephemeral}"
SSH_TMPDIR=""

setup_ssh_key() {
    if [[ "$SSH_KEY_FILE" == "ephemeral" ]]; then
        echo "Generating ephemeral SSH keypair for build..."
        SSH_TMPDIR=$(mktemp -d)
        ssh-keygen -t ed25519 -f "$SSH_TMPDIR/key" -N "" -q
        SSH_PRIVATE_KEY="$SSH_TMPDIR/key"
        SSH_PUBLIC_KEY_CONTENT=$(cat "$SSH_TMPDIR/key.pub")
        echo "  Private key: $SSH_PRIVATE_KEY"
    else
        # Use existing key
        SSH_PRIVATE_KEY=$(eval echo "$SSH_KEY_FILE")  # Expand ~
        SSH_PUBLIC_KEY_FILE="${SSH_PRIVATE_KEY}.pub"

        if [[ ! -f "$SSH_PRIVATE_KEY" ]]; then
            echo "Error: SSH private key not found: $SSH_PRIVATE_KEY"
            echo ""
            echo "Options:"
            echo "  1. Generate a key: ssh-keygen -t ed25519"
            echo "  2. Use ephemeral key: unset SSH_KEY_FILE (default)"
            echo "  3. Specify different key: SSH_KEY_FILE=/path/to/key ./build.sh"
            exit 1
        fi

        if [[ ! -f "$SSH_PUBLIC_KEY_FILE" ]]; then
            echo "Error: SSH public key not found: $SSH_PUBLIC_KEY_FILE"
            echo "Expected public key alongside private key"
            exit 1
        fi

        SSH_PUBLIC_KEY_CONTENT=$(cat "$SSH_PUBLIC_KEY_FILE")
        echo "Using existing SSH key: $SSH_PRIVATE_KEY"
    fi
}

cleanup_ssh_key() {
    if [[ -n "$SSH_TMPDIR" && -d "$SSH_TMPDIR" ]]; then
        rm -rf "$SSH_TMPDIR"
    fi
}
trap cleanup_ssh_key EXIT

# Generate versioned image name from version file
# Outputs: deb12.8-custom or deb13.1-pve9.2-custom
generate_versioned_name() {
    local image_dir="$1"
    local template_name="$2"
    local version_file="${image_dir}/image-version.txt"

    if [[ ! -f "$version_file" ]]; then
        echo "$template_name"
        return
    fi

    # Read version info
    local debian_version pve_version
    debian_version=$(grep '^DEBIAN_VERSION=' "$version_file" | cut -d'=' -f2)
    pve_version=$(grep '^PVE_VERSION=' "$version_file" | cut -d'=' -f2)

    # Extract variant from template name (e.g., "custom" from "debian-12-custom")
    local variant
    variant=$(echo "$template_name" | sed 's/debian-[0-9]*-//')

    # Build versioned name
    # Format: debX.Y-variant or debX.Y-pveA.B-variant
    local versioned_name
    if [[ -n "$pve_version" ]]; then
        versioned_name="deb${debian_version}-pve${pve_version}-${variant}"
    else
        versioned_name="deb${debian_version}-${variant}"
    fi

    echo "$versioned_name"
}

# Rename image with version info
rename_with_version() {
    local image_dir="$1"
    local template_name="$2"
    local original_image="${image_dir}/${template_name}.qcow2"

    if [[ ! -f "$original_image" ]]; then
        echo "Warning: Original image not found at $original_image"
        return 1
    fi

    local versioned_name
    versioned_name=$(generate_versioned_name "$image_dir" "$template_name")

    if [[ "$versioned_name" == "$template_name" ]]; then
        echo "No version info available, keeping original name"
        return 0
    fi

    local versioned_image="${image_dir}/${versioned_name}.qcow2"

    echo ""
    echo "Renaming image with version info..."
    echo "  From: ${template_name}.qcow2"
    echo "  To:   ${versioned_name}.qcow2"
    mv "$original_image" "$versioned_image"

    # Create backward-compatible symlink (debian-12-custom.qcow2 -> deb12.8-custom.qcow2)
    echo "  Creating compatibility symlink: ${template_name}.qcow2 -> ${versioned_name}.qcow2"
    ln -sf "${versioned_name}.qcow2" "$original_image"

    # Store versioned name for checksum generation
    echo "$versioned_name" > "${image_dir}/.versioned-name"

    return 0
}

# Generate SHA256 checksum for built image (per-image .sha256 file)
generate_checksum() {
    local image_dir="$1"
    local template_name="$2"

    # Check if we have a versioned name
    local image_name="$template_name"
    if [[ -f "${image_dir}/.versioned-name" ]]; then
        image_name=$(cat "${image_dir}/.versioned-name")
    fi

    local image_path="${image_dir}/${image_name}.qcow2"
    local checksum_file="${image_dir}/${image_name}.qcow2.sha256"

    if [[ ! -f "$image_path" ]]; then
        echo "Warning: Image not found at $image_path"
        return 1
    fi

    echo "Generating SHA256 checksum..."
    (cd "$image_dir" && sha256sum "${image_name}.qcow2" > "${image_name}.qcow2.sha256")
    echo "Checksum saved to: $checksum_file"
    cat "$checksum_file"
}

# Find available templates (per-template directory structure)
templates=(templates/*/template.pkr.hcl)

if [[ ${#templates[@]} -eq 0 ]]; then
    echo "No templates found in templates/"
    exit 1
fi

# Check for command-line argument (non-interactive mode)
if [[ $# -gt 0 ]]; then
    name="$1"
    template="templates/${name}/template.pkr.hcl"
    if [[ ! -f "$template" ]]; then
        echo "Error: Template not found: $template"
        echo "Available templates:"
        for t in templates/*/template.pkr.hcl; do
            echo "  $(basename "$(dirname "$t")")"
        done
        exit 1
    fi
else
    # Interactive mode - display menu
    echo "Available templates:"
    echo ""
    for i in "${!templates[@]}"; do
        tname=$(basename "$(dirname "${templates[$i]}")")
        printf "  %d) %s\n" $((i + 1)) "$tname"
    done
    echo ""

    # Get selection
    read -p "Select template [1-${#templates[@]}]: " selection

    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#templates[@]} ]]; then
        echo "Invalid selection"
        exit 1
    fi

    template="${templates[$((selection - 1))]}"
    name=$(basename "$(dirname "$template")")
fi
timestamp=$(date +%Y%m%d-%H%M%S)
logfile="logs/${name}.${timestamp}.log"

# Ensure logs directory exists
mkdir -p logs

echo ""
echo "Building: $template"
echo "Log file: $logfile"
echo ""

# Setup SSH key (ephemeral by default)
setup_ssh_key

# Run packer with logging and SSH key variables
packer build -force \
    -var "ssh_private_key_file=$SSH_PRIVATE_KEY" \
    -var "ssh_public_key=$SSH_PUBLIC_KEY_CONTENT" \
    "$template" 2>&1 | tee "$logfile"

echo ""
echo "Build complete. Log saved to: $logfile"

# Post-build: rename image with version info and generate checksum
# Output directory follows template pattern:
# debian-12-custom -> images/debian-12
# debian-13-custom -> images/debian-13
# debian-13-pve -> images/debian-13-pve
if [[ "$name" == *-custom ]]; then
    # Strip "-custom" suffix for directory (debian-12-custom -> debian-12)
    dir_name="${name%-custom}"
else
    # Keep full name for non-custom templates (debian-13-pve)
    dir_name="$name"
fi
image_dir="images/${dir_name}"
if [[ -d "$image_dir" ]]; then
    # Rename with version info (if available)
    rename_with_version "$image_dir" "$name" || true

    # Generate checksum for the (possibly renamed) image
    echo ""
    generate_checksum "$image_dir" "$name"

    # Show final image name
    echo ""
    if [[ -f "${image_dir}/.versioned-name" ]]; then
        versioned=$(cat "${image_dir}/.versioned-name")
        echo "Final image: ${image_dir}/${versioned}.qcow2"
    else
        echo "Final image: ${image_dir}/${name}.qcow2"
    fi
fi
