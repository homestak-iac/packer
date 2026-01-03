#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

DEST_DIR="/var/lib/vz/template/iso"

# Map of source images to destination names
declare -A IMAGES=(
    ["images/debian-12/debian-12-base.qcow2"]="debian-12-packer.img"
    ["images/debian-13/debian-13-base.qcow2"]="debian-13-packer.img"
)

echo "Publishing packer images to Proxmox storage..."
echo ""

published=0
for src in "${!IMAGES[@]}"; do
    dest="${DEST_DIR}/${IMAGES[$src]}"

    if [[ -f "$src" ]]; then
        echo "  $src -> $dest"
        cp "$src" "$dest"
        published=$((published + 1))
    else
        echo "  $src (not found, skipping)"
    fi
done

echo ""
if [[ $published -gt 0 ]]; then
    echo "Published $published image(s) to $DEST_DIR"
else
    echo "No images found. Run build.sh first."
    exit 1
fi
