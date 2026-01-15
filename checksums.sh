#!/bin/bash
# Generate or verify SHA256 checksums for packer images
# Uses per-image .sha256 files (Debian convention)
set -euo pipefail

cd "$(dirname "$0")"

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  generate    Generate .sha256 files for all images"
    echo "  verify      Verify checksums for all images"
    echo "  show        Display current checksums"
    echo ""
}

generate_checksums() {
    local found=0

    echo "Generating per-image checksums..."
    echo ""

    for image in images/*/*.qcow2; do
        [[ -f "$image" ]] || continue
        # Skip symlinks (backward-compat links)
        [[ -L "$image" ]] && continue
        found=$((found + 1))

        local checksum_file="${image}.sha256"
        local dir=$(dirname "$image")
        local basename=$(basename "$image")

        # Generate checksum with just filename (not path)
        (cd "$dir" && sha256sum "$basename" > "${basename}.sha256")
        echo "  $checksum_file"
    done

    if [[ $found -eq 0 ]]; then
        echo "No images found in images/"
        return 1
    fi

    echo ""
    echo "Generated checksums for $found image(s)"
}

verify_checksums() {
    local found=0
    local failed=0

    echo "Verifying per-image checksums..."
    echo ""

    for checksum_file in images/*/*.sha256; do
        [[ -f "$checksum_file" ]] || continue
        found=$((found + 1))

        local dir=$(dirname "$checksum_file")

        echo -n "  $checksum_file: "
        if (cd "$dir" && sha256sum -c "$(basename "$checksum_file")" --quiet 2>/dev/null); then
            echo "OK"
        else
            echo "FAILED"
            failed=$((failed + 1))
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo "No checksum files found"
        echo "Run '$0 generate' first or build images with build.sh"
        return 1
    fi

    echo ""
    if [[ $failed -eq 0 ]]; then
        echo "All $found checksum(s) verified successfully"
        return 0
    else
        echo "FAILED: $failed of $found checksum(s) failed verification"
        return 1
    fi
}

show_checksums() {
    local found=0

    echo "Current image checksums:"
    echo ""

    for checksum_file in images/*/*.sha256; do
        [[ -f "$checksum_file" ]] || continue
        found=$((found + 1))

        echo "=== $checksum_file ==="
        cat "$checksum_file"
        echo ""
    done

    # Also show legacy SHA256SUMS if present
    for legacy_file in images/*/SHA256SUMS SHA256SUMS; do
        if [[ -f "$legacy_file" ]]; then
            echo "=== $legacy_file (legacy) ==="
            cat "$legacy_file"
            echo ""
            found=$((found + 1))
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo "No checksum files found"
        echo "Run '$0 generate' or build images with build.sh"
        return 1
    fi
}

# Main
case "${1:-}" in
    generate)
        generate_checksums
        ;;
    verify)
        verify_checksums
        ;;
    show)
        show_checksums
        ;;
    *)
        usage
        exit 1
        ;;
esac
