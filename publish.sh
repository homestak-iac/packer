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
