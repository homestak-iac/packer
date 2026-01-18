#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# -----------------------------------------------------------------------------
# Cache Management Options
# -----------------------------------------------------------------------------

CLEAN_CACHE=false
AUTO_UPDATE=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [TEMPLATE]

Build packer images with optional cache management.

Options:
  --clean-cache    Clear cached base images before building
  --auto-update    Automatically clear stale cache and retry on checksum mismatch
  --help, -h       Show this help message

Arguments:
  TEMPLATE         Template name (e.g., debian-12-custom). If omitted, shows menu.

Examples:
  $(basename "$0")                           # Interactive menu
  $(basename "$0") debian-12-custom          # Build specific template
  $(basename "$0") --clean-cache debian-13-pve  # Fresh build, no cache
  $(basename "$0") --auto-update debian-12-custom  # Auto-retry on stale cache

Environment:
  SSH_KEY_FILE     Path to SSH key (default: generates ephemeral key)
EOF
    exit 0
}

clean_cache() {
    local template_name="$1"

    # Map template to cache file
    # debian-12-custom, debian-13-custom -> debian-{12,13}-generic-amd64.qcow2
    # debian-13-pve -> debian-13-generic-amd64.qcow2
    local debian_version
    debian_version=$(echo "$template_name" | grep -oP 'debian-\K[0-9]+')
    local cache_file="cache/debian-${debian_version}-generic-amd64.qcow2"

    if [[ -f "$cache_file" ]]; then
        echo "Clearing cached base image: $cache_file"
        rm -f "$cache_file"
    else
        echo "No cached base image found for $template_name"
    fi
}

clean_all_cache() {
    echo "Clearing all cached base images..."
    rm -f cache/*.qcow2 2>/dev/null || true
    echo "Cache cleared."
}

# Parse command-line options
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean-cache)
            CLEAN_CACHE=true
            shift
            ;;
        --auto-update)
            AUTO_UPDATE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

# -----------------------------------------------------------------------------
# SSH Key Handling
# -----------------------------------------------------------------------------

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
    # Format: debX.Y-variant or debX.Y-pveA.B[-variant]
    # When variant is "pve" and pve_version exists, omit redundant suffix
    local versioned_name
    if [[ -n "$pve_version" ]]; then
        if [[ "$variant" == "pve" ]]; then
            # Variant already captured in pve version (e.g., deb13.3-pve9.1)
            versioned_name="deb${debian_version}-pve${pve_version}"
        else
            # Non-pve variant with PVE installed (e.g., deb13.3-pve9.1-custom)
            versioned_name="deb${debian_version}-pve${pve_version}-${variant}"
        fi
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

# Split large image into parts for GitHub release upload (2GB limit)
# Uses ~1.9GB parts to stay safely under limit with margin
split_large_image() {
    local image_dir="$1"
    local image_name="$2"
    local image_path="${image_dir}/${image_name}.qcow2"

    # GitHub release asset limit is 2GB; use 1.9GB for safety margin
    local threshold=$((1900 * 1024 * 1024))  # 1.9 GiB in bytes
    local split_size="1900m"  # split command format

    if [[ ! -f "$image_path" ]]; then
        return 0  # Nothing to split
    fi

    local size
    size=$(stat -c%s "$image_path" 2>/dev/null || stat -f%z "$image_path" 2>/dev/null)

    if [[ -z "$size" ]]; then
        echo "Warning: Could not determine image size"
        return 0
    fi

    if [[ "$size" -le "$threshold" ]]; then
        echo "Image size ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size} bytes")) is under 2GB, no split needed"
        return 0
    fi

    echo ""
    echo "Image size ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size} bytes")) exceeds 2GB GitHub limit"
    echo "Splitting into ~1.9GB parts..."

    # Split into parts with .part suffix (partaa, partab, etc.)
    (cd "$image_dir" && split -b "$split_size" "${image_name}.qcow2" "${image_name}.qcow2.part")

    # Verify split created parts
    local parts
    parts=$(ls "${image_dir}/${image_name}.qcow2.part"* 2>/dev/null | wc -l)
    if [[ "$parts" -eq 0 ]]; then
        echo "Warning: Split failed, keeping original file"
        return 1
    fi

    echo "Created $parts parts:"
    ls -lh "${image_dir}/${image_name}.qcow2.part"* | awk '{print "  " $NF ": " $5}'

    # Remove original to save space (parts can be reassembled with cat)
    rm -f "$image_path"
    echo "Removed original (reassemble with: cat ${image_name}.qcow2.part* > ${image_name}.qcow2)"

    # Mark that this image was split
    echo "split" > "${image_dir}/.split-status"

    return 0
}

# Generate SHA256 checksum for built image (per-image .sha256 file)
# Handles both regular images and split images
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

    # Check if image was split
    if [[ -f "${image_dir}/.split-status" ]]; then
        echo "Generating SHA256 checksum for split image (reassembling for checksum)..."
        # Generate checksum by piping cat output to sha256sum (doesn't create temp file)
        local checksum
        checksum=$(cat "${image_dir}/${image_name}.qcow2.part"* | sha256sum | awk '{print $1}')
        echo "$checksum  ${image_name}.qcow2" > "$checksum_file"
        echo "Checksum saved to: $checksum_file"
        cat "$checksum_file"
        return 0
    fi

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

# Handle --clean-cache: clear cache before building
if [[ "$CLEAN_CACHE" == "true" ]]; then
    clean_cache "$name"
    echo ""
fi

# Setup SSH key (ephemeral by default)
setup_ssh_key

# Function to run packer build
run_packer_build() {
    packer build -force \
        -var "ssh_private_key_file=$SSH_PRIVATE_KEY" \
        -var "ssh_public_key=$SSH_PUBLIC_KEY_CONTENT" \
        "$template" 2>&1 | tee "$logfile"
    return "${PIPESTATUS[0]}"
}

# Function to check if failure was due to checksum mismatch
is_checksum_error() {
    grep -q "Checksum did not match" "$logfile" 2>/dev/null || \
    grep -q "checksum.*mismatch" "$logfile" 2>/dev/null || \
    grep -q "SHA256 checksum" "$logfile" 2>/dev/null
}

# Run packer build with optional auto-update retry
set +e  # Temporarily allow errors for build retry logic
if run_packer_build; then
    BUILD_SUCCESS=true
else
    BUILD_SUCCESS=false

    if [[ "$AUTO_UPDATE" == "true" ]] && is_checksum_error; then
        echo ""
        echo "Checksum mismatch detected. Clearing cache and retrying..."
        clean_cache "$name"
        echo ""

        if run_packer_build; then
            BUILD_SUCCESS=true
        fi
    fi
fi
set -e  # Re-enable strict error handling

if [[ "$BUILD_SUCCESS" != "true" ]]; then
    echo ""
    echo "Build failed. Log saved to: $logfile"

    # Check if it was a checksum error and suggest options
    if is_checksum_error && [[ "$AUTO_UPDATE" != "true" ]]; then
        echo ""
        echo "This appears to be a checksum mismatch (upstream image may have changed)."
        echo "Options:"
        echo "  1. Retry with --auto-update: $(basename "$0") --auto-update $name"
        echo "  2. Clear cache manually: rm -f cache/debian-*-generic-amd64.qcow2"
        echo "  3. Clear cache and rebuild: $(basename "$0") --clean-cache $name"
    fi
    exit 1
fi

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

    # Get the final image name for split and checksum
    final_name="$name"
    if [[ -f "${image_dir}/.versioned-name" ]]; then
        final_name=$(cat "${image_dir}/.versioned-name")
    fi

    # Split large images for GitHub release upload (>2GB)
    echo ""
    split_large_image "$image_dir" "$final_name"

    # Generate checksum for the (possibly split) image
    echo ""
    generate_checksum "$image_dir" "$name"

    # Show final image name
    echo ""
    if [[ -f "${image_dir}/.split-status" ]]; then
        echo "Final image: ${image_dir}/${final_name}.qcow2.part* (split for GitHub upload)"
        echo "  Reassemble: cat ${final_name}.qcow2.part* > ${final_name}.qcow2"
    else
        echo "Final image: ${image_dir}/${final_name}.qcow2"
    fi
fi
