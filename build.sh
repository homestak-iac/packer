#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

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
logfile="logs/${name}-${timestamp}.log"

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
