#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# Generate SHA256 checksum for built image
generate_checksum() {
    local image_dir="$1"
    local image_name="$2"
    local image_path="${image_dir}/${image_name}.qcow2"
    local checksum_file="${image_dir}/SHA256SUMS"

    if [[ ! -f "$image_path" ]]; then
        echo "Warning: Image not found at $image_path"
        return 1
    fi

    echo "Generating SHA256 checksum..."
    (cd "$image_dir" && sha256sum "${image_name}.qcow2" > SHA256SUMS)
    echo "Checksum saved to: $checksum_file"
    cat "$checksum_file"
}

# Find available templates
templates=(templates/*.pkr.hcl)

if [[ ${#templates[@]} -eq 0 ]]; then
    echo "No templates found in templates/"
    exit 1
fi

# Display menu
echo "Available templates:"
echo ""
for i in "${!templates[@]}"; do
    name=$(basename "${templates[$i]}" .pkr.hcl)
    printf "  %d) %s\n" $((i + 1)) "$name"
done
echo ""

# Get selection
read -p "Select template [1-${#templates[@]}]: " selection

if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#templates[@]} ]]; then
    echo "Invalid selection"
    exit 1
fi

template="${templates[$((selection - 1))]}"
name=$(basename "$template" .pkr.hcl)
timestamp=$(date +%Y%m%d-%H%M%S)
logfile="logs/${name}.${timestamp}.log"

# Ensure logs directory exists
mkdir -p logs

echo ""
echo "Building: $template"
echo "Log file: $logfile"
echo ""

# Run packer with logging
packer build -force "$template" 2>&1 | tee "$logfile"

echo ""
echo "Build complete. Log saved to: $logfile"

# Generate checksum for the built image
image_dir="images/${name}"
if [[ -d "$image_dir" ]]; then
    echo ""
    generate_checksum "$image_dir" "$name"
fi
