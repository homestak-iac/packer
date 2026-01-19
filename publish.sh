#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# Git-derived version (do not use hardcoded VERSION constant)
get_version() {
    git describe --tags --abbrev=0 2>/dev/null || echo "dev"
}

DEST_DIR="/var/lib/vz/template/iso"
DRY_RUN=false

show_help() {
    cat << 'EOF'
publish.sh - Publish packer images to Proxmox VE storage

Usage:
  publish.sh [options]

Options:
  --help, -h    Show this help message
  --version     Show version
  --dry-run     Show what would be copied without making changes

Description:
  Copies built packer images from images/ to the Proxmox VE ISO storage
  directory (/var/lib/vz/template/iso/). Images are compressed during copy
  using qemu-img convert.

  Only copies images that are newer than the destination or don't exist.
  Creates backward-compatible symlinks for versioned images.

Examples:
  ./publish.sh            # Publish all built images
  ./publish.sh --dry-run  # Preview what would be published
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            ;;
        --version)
            echo "publish.sh $(get_version)"
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY-RUN: Previewing packer image publication..."
else
    echo "Publishing packer images to Proxmox storage..."
fi
echo ""

found=0
updated=0
for src in images/*/*.qcow2; do
    [[ -f "$src" ]] || continue
    # Skip symlinks (compatibility links)
    [[ -L "$src" ]] && continue
    found=$((found + 1))

    # debian-12-custom.qcow2 -> debian-12-custom.img
    destname="$(basename "$src" .qcow2).img"
    dest="${DEST_DIR}/${destname}"

    # Check if destination exists and is newer than source
    if [[ -f "$dest" && "$dest" -nt "$src" ]]; then
        echo "  $src (unchanged)"
        continue
    fi

    # Compress and copy using qemu-img convert
    # This reclaims sparse space and applies zlib compression
    src_size=$(du -h "$src" | cut -f1)
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [would copy] $src ($src_size) -> $dest"
    else
        echo "  $src ($src_size) -> $dest (compressing...)"
        qemu-img convert -c -O qcow2 "$src" "$dest"
        dest_size=$(du -h "$dest" | cut -f1)
        echo "    compressed: $src_size -> $dest_size"
    fi
    updated=$((updated + 1))
done

echo ""
if [[ $found -eq 0 ]]; then
    echo "No images found in images/. Run build.sh first."
    exit 1
elif [[ $updated -gt 0 ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would update $updated of $found image(s)"
    else
        echo "Updated $updated of $found image(s)"
    fi
else
    echo "All $found image(s) up to date"
fi

# Copy checksum files
checksum_count=0
for checksum in images/*/SHA256SUMS; do
    [[ -f "$checksum" ]] || continue
    image_name=$(basename "$(dirname "$checksum")")
    dest="${DEST_DIR}/${image_name}.SHA256SUMS"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [would copy] $checksum -> $dest"
    else
        cp "$checksum" "$dest"
    fi
    checksum_count=$((checksum_count + 1))
done

if [[ $checksum_count -gt 0 ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would copy $checksum_count checksum file(s)"
    else
        echo "Copied $checksum_count checksum file(s)"
    fi
fi

# Create backward-compatible symlinks for versioned images
# This allows tofu/site-config to reference images by template name (debian-12-custom.img)
symlink_count=0
for versioned_file in images/*/.versioned-name; do
    [[ -f "$versioned_file" ]] || continue
    image_dir=$(dirname "$versioned_file")
    template_name=$(basename "$image_dir")
    versioned_name=$(cat "$versioned_file")

    # Create symlink: debian-12-custom.img -> deb12.8-custom.img
    if [[ "$template_name" != "$versioned_name" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [would create symlink] ${template_name}.img -> ${versioned_name}.img"
        else
            ln -sf "${versioned_name}.img" "${DEST_DIR}/${template_name}.img"
            echo "  Created symlink: ${template_name}.img -> ${versioned_name}.img"
        fi
        symlink_count=$((symlink_count + 1))
    fi
done

if [[ $symlink_count -gt 0 ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would create $symlink_count compatibility symlink(s)"
    else
        echo "Created $symlink_count compatibility symlink(s)"
    fi
fi
