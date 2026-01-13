#!/bin/bash
# Generate or verify SHA256 checksums for packer images
set -euo pipefail

cd "$(dirname "$0")"

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  generate    Generate SHA256SUMS for all images"
    echo "  verify      Verify checksums for all images"
    echo "  show        Display current checksums"
    echo ""
}

generate_checksums() {
    local output_file="${1:-SHA256SUMS}"
    local found=0

    echo "Generating checksums for all images..."
    echo ""

    # Clear or create output file
    > "$output_file"

    for image in images/*/*.qcow2; do
        [[ -f "$image" ]] || continue
        found=$((found + 1))

        # Generate checksum with relative path
        sha256sum "$image" >> "$output_file"
        echo "  $image"
    done

    if [[ $found -eq 0 ]]; then
        echo "No images found in images/"
        rm -f "$output_file"
        return 1
    fi

    echo ""
    echo "Generated checksums for $found image(s): $output_file"
    echo ""
    cat "$output_file"
}

verify_checksums() {
    local checksum_file="${1:-SHA256SUMS}"

    if [[ ! -f "$checksum_file" ]]; then
        echo "Checksum file not found: $checksum_file"
        echo "Run '$0 generate' first"
        return 1
    fi

    echo "Verifying checksums from: $checksum_file"
    echo ""

    if sha256sum -c "$checksum_file"; then
        echo ""
        echo "All checksums verified successfully"
        return 0
    else
        echo ""
        echo "Checksum verification FAILED"
        return 1
    fi
}

show_checksums() {
    local found=0

    echo "Current image checksums:"
    echo ""

    for checksum_file in images/*/SHA256SUMS; do
        [[ -f "$checksum_file" ]] || continue
        found=$((found + 1))

        echo "=== $(dirname "$checksum_file") ==="
        cat "$checksum_file"
        echo ""
    done

    if [[ -f "SHA256SUMS" ]]; then
        echo "=== Combined SHA256SUMS ==="
        cat SHA256SUMS
        found=$((found + 1))
    fi

    if [[ $found -eq 0 ]]; then
        echo "No checksum files found"
        echo "Run '$0 generate' or build images with build.sh"
        return 1
    fi
}

# Main
case "${1:-}" in
    generate)
        generate_checksums "${2:-SHA256SUMS}"
        ;;
    verify)
        verify_checksums "${2:-SHA256SUMS}"
        ;;
    show)
        show_checksums
        ;;
    *)
        usage
        exit 1
        ;;
esac
