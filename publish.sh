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

    if rsync -c --info=skip1,name1 "$src" "$dest" | grep -q .; then
        echo "  $src -> $dest (updated)"
        updated=$((updated + 1))
    else
        echo "  $src (unchanged)"
    fi
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
