#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# Git-derived version (do not use hardcoded VERSION constant)
get_version() {
    git describe --tags --abbrev=0 2>/dev/null || echo "dev"
}

# -----------------------------------------------------------------------------
# Cache Management Options
# -----------------------------------------------------------------------------

CLEAN_CACHE=false
AUTO_UPDATE=false
FORCE_BUILD=false

usage() {
    cat <<EOF
build.sh $(get_version) - Build packer images with optional cache management

Usage: $(basename "$0") [OPTIONS] [TEMPLATE]

Options:
  --help, -h       Show this help message
  --version        Show version
  --force          Rebuild even if cache is valid
  --clean-cache    Clear cached base images before building
  --auto-update    Automatically clear stale cache and retry on checksum mismatch

Arguments:
  TEMPLATE         Template name (e.g., debian-12, pve-9). If omitted, shows menu.

Examples:
  $(basename "$0")                           # Interactive menu
  $(basename "$0") debian-12                 # Build specific template (uses cache)
  $(basename "$0") --force debian-12         # Force rebuild, ignore cache
  $(basename "$0") --clean-cache pve-9       # Fresh build, no base image cache
  $(basename "$0") --auto-update debian-13   # Auto-retry on stale cache

Environment:
  SSH_KEY_FILE     Path to SSH key (default: generates ephemeral key)
EOF
    exit 0
}

clean_cache() {
    local template_name="$1"

    # Extract cache file path from template HCL
    local template_file="templates/${template_name}/template.pkr.hcl"
    if [[ ! -f "$template_file" ]]; then
        echo "Warning: Template not found: $template_file"
        return
    fi

    local cache_file
    cache_file=$(grep 'iso_target_path' "$template_file" | grep -oP '"[^"]*"' | tr -d '"')

    if [[ -z "$cache_file" ]]; then
        echo "Warning: Could not determine cache file for $template_name"
        return
    fi

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

# -----------------------------------------------------------------------------
# Built Image Caching
# -----------------------------------------------------------------------------

# Compute a composite cache key from source image + template files.
# Cache key = SHA256(source_image_checksum + template_files_hash)
compute_cache_key() {
    local template_name="$1"

    # Files that contribute to the cache key
    local files=(
        "templates/${template_name}/template.pkr.hcl"
        "templates/${template_name}/cleanup.sh"
        "shared/scripts/cleanup-common.sh"
        "shared/scripts/detect-versions.sh"
        "shared/cloud-init/user-data.pkrtpl"
        "shared/cloud-init/meta-data"
    )

    # Hash template files (sort for determinism)
    local template_hash
    template_hash=$(cat "${files[@]}" 2>/dev/null | sha256sum | awk '{print $1}')

    # Get source cloud image checksum (from cached download)
    local cache_file
    cache_file=$(grep 'iso_target_path' "templates/${template_name}/template.pkr.hcl" \
        | grep -oP '"[^"]*"' | tr -d '"')

    local source_hash="none"
    if [[ -n "$cache_file" && -f "$cache_file" ]]; then
        source_hash=$(sha256sum "$cache_file" | awk '{print $1}')
    fi

    # Composite key: hash of both components
    echo "${source_hash}:${template_hash}" | sha256sum | awk '{print $1}'
}

# Check if cached build is still valid. Returns 0 (cache hit) or 1 (cache miss).
check_build_cache() {
    local template_name="$1"
    local cache_key_file="images/${template_name}/.cache-key"
    local image_file="images/${template_name}/${template_name}.qcow2"

    # No cache key file → miss
    if [[ ! -f "$cache_key_file" ]]; then
        echo "Cache miss: no .cache-key file"
        return 1
    fi

    # No built image (and no split parts) → miss
    if [[ ! -f "$image_file" ]] && ! ls "images/${template_name}/${template_name}.qcow2.part"* &>/dev/null; then
        echo "Cache miss: no built image"
        return 1
    fi

    local stored_key current_key
    stored_key=$(cat "$cache_key_file")
    current_key=$(compute_cache_key "$template_name")

    if [[ "$stored_key" == "$current_key" ]]; then
        echo "Cache hit: built image is up to date"
        return 0
    else
        echo "Cache miss: template or source image changed"
        return 1
    fi
}

# Write cache key after successful build
write_cache_key() {
    local template_name="$1"
    local cache_key_file="images/${template_name}/.cache-key"

    compute_cache_key "$template_name" > "$cache_key_file"
}

# Parse command-line options
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_BUILD=true
            shift
            ;;
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
        --version)
            echo "build.sh $(get_version)"
            exit 0
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
    # shellcheck disable=SC2012 # filenames are controlled, ls is safe here
    parts=$(ls "${image_dir}/${image_name}.qcow2.part"* 2>/dev/null | wc -l)
    if [[ "$parts" -eq 0 ]]; then
        echo "Warning: Split failed, keeping original file"
        return 1
    fi

    echo "Created $parts parts:"
    # shellcheck disable=SC2012 # filenames are controlled, ls is safe here
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
    local image_name="$2"
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
    read -rp "Select template [1-${#templates[@]}]: " selection

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

# Check build cache (skip rebuild if valid, unless --force)
if [[ "$FORCE_BUILD" != "true" ]]; then
    if check_build_cache "$name"; then
        echo "Skipping build (use --force to rebuild)"
        exit 0
    fi
else
    echo "Force build requested, ignoring cache"
fi
echo ""

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

# Post-build: generate checksum
# Template name = directory name = image name (stable naming)
image_dir="images/${name}"
if [[ -d "$image_dir" ]]; then
    # Split large images for GitHub release upload (>2GB)
    echo ""
    split_large_image "$image_dir" "$name"

    # Generate checksum for the (possibly split) image
    echo ""
    generate_checksum "$image_dir" "$name"

    # Write cache key for future builds
    write_cache_key "$name"
    echo "Cache key written to: ${image_dir}/.cache-key"

    # Show final image name
    echo ""
    if [[ -f "${image_dir}/.split-status" ]]; then
        echo "Final image: ${image_dir}/${name}.qcow2.part* (split for GitHub upload)"
        echo "  Reassemble: cat ${name}.qcow2.part* > ${name}.qcow2"
    else
        echo "Final image: ${image_dir}/${name}.qcow2"
    fi
fi
