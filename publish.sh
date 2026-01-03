#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

DEST_DIR="/var/lib/vz/template/iso"

echo "Publishing packer images to Proxmox storage..."
echo ""

published=0
for src in images/*/*.qcow2; do
    [[ -f "$src" ]] || continue

    # debian-12-base.qcow2 -> debian-12-custom.img
    basename=$(basename "$src" .qcow2)
    destname="${basename%-base}-custom.img"
    dest="${DEST_DIR}/${destname}"

    echo "  $src -> $dest"
    cp "$src" "$dest"
    published=$((published + 1))
done

echo ""
if [[ $published -gt 0 ]]; then
    echo "Published $published image(s) to $DEST_DIR"
else
    echo "No images found in images/. Run build.sh first."
    exit 1
fi
