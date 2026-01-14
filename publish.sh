#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

DEST_DIR="/var/lib/vz/template/iso"

echo "Publishing packer images to Proxmox storage..."
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
    echo "  $src ($src_size) -> $dest (compressing...)"
    qemu-img convert -c -O qcow2 "$src" "$dest"
    dest_size=$(du -h "$dest" | cut -f1)
    echo "    compressed: $src_size -> $dest_size"
    updated=$((updated + 1))
done

echo ""
if [[ $found -eq 0 ]]; then
    echo "No images found in images/. Run build.sh first."
    exit 1
elif [[ $updated -gt 0 ]]; then
    echo "Updated $updated of $found image(s)"
else
    echo "All $found image(s) up to date"
fi

# Copy checksum files
checksum_count=0
for checksum in images/*/SHA256SUMS; do
    [[ -f "$checksum" ]] || continue
    image_name=$(basename "$(dirname "$checksum")")
    dest="${DEST_DIR}/${image_name}.SHA256SUMS"
    cp "$checksum" "$dest"
    checksum_count=$((checksum_count + 1))
done

if [[ $checksum_count -gt 0 ]]; then
    echo "Copied $checksum_count checksum file(s)"
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
        ln -sf "${versioned_name}.img" "${DEST_DIR}/${template_name}.img"
        echo "  Created symlink: ${template_name}.img -> ${versioned_name}.img"
        symlink_count=$((symlink_count + 1))
    fi
done

if [[ $symlink_count -gt 0 ]]; then
    echo "Created $symlink_count compatibility symlink(s)"
fi
