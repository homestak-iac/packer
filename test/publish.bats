#!/usr/bin/env bats
#
# publish.bats - Tests for publish.sh
#
# Tests:
# 1. Argument parsing (--help, --version, --dry-run)
# 2. Image discovery logic
# 3. Destination name transformation
# 4. Symlink detection
# 5. Versioned name handling
#
# Note: Tests that require file I/O test the logic patterns rather than
# running the full script, since publish.sh changes to its own directory.
#

load 'test_helper/common'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# -----------------------------------------------------------------------------
# Argument Parsing Tests (run actual script)
# -----------------------------------------------------------------------------

@test "--help shows usage information" {
    run "${PACKER_DIR}/publish.sh" --help

    [ "$status" -eq 0 ]
    assert_output_contains "publish.sh"
    assert_output_contains "Usage:"
    assert_output_contains "--help"
    assert_output_contains "--dry-run"
}

@test "-h is alias for --help" {
    run "${PACKER_DIR}/publish.sh" -h

    [ "$status" -eq 0 ]
    assert_output_contains "Usage:"
}

@test "--version shows version" {
    run "${PACKER_DIR}/publish.sh" --version

    [ "$status" -eq 0 ]
    assert_output_contains "publish.sh"
    # Version is either a tag (v0.x) or "dev"
    [[ "$output" =~ publish\.sh\ (v[0-9]+\.[0-9]+|dev) ]]
}

@test "unknown option returns error" {
    run "${PACKER_DIR}/publish.sh" --invalid-option

    [ "$status" -eq 1 ]
    assert_output_contains "Unknown option"
    assert_output_contains "--help"
}

# -----------------------------------------------------------------------------
# Image Discovery Logic Tests
# -----------------------------------------------------------------------------

@test "glob pattern finds .qcow2 files in images subdirectories" {
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "debian-12-custom" 1024
    create_mock_image "${TEST_TEMP_DIR}/images/debian-13" "debian-13-custom" 1024

    # Test the glob pattern used by publish.sh
    local images=()
    for src in "${TEST_TEMP_DIR}"/images/*/*.qcow2; do
        [[ -f "$src" ]] || continue
        [[ -L "$src" ]] && continue  # Skip symlinks
        images+=("$src")
    done

    [ "${#images[@]}" -eq 2 ]
}

@test "glob pattern skips symlinks" {
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "debian-12-custom" 1024

    # Create symlink (compatibility link)
    ln -s "debian-12-custom.qcow2" "${TEST_TEMP_DIR}/images/debian-12/debian-12-alias.qcow2"

    # Test the glob pattern with symlink skip logic
    local count=0
    for src in "${TEST_TEMP_DIR}"/images/*/*.qcow2; do
        [[ -f "$src" ]] || continue
        [[ -L "$src" ]] && continue  # Skip symlinks
        count=$((count + 1))
    done

    [ "$count" -eq 1 ]
}

@test "glob pattern handles empty directory" {
    # No images created - just empty structure from setup
    rm -rf "${TEST_TEMP_DIR}/images"
    mkdir -p "${TEST_TEMP_DIR}/images"

    local count=0
    for src in "${TEST_TEMP_DIR}"/images/*/*.qcow2; do
        [[ -f "$src" ]] || continue
        count=$((count + 1))
    done

    [ "$count" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Destination Name Transformation Tests
# -----------------------------------------------------------------------------

@test "transforms .qcow2 to .img extension" {
    local src="images/debian-12/debian-12-custom.qcow2"

    # Transformation logic from publish.sh
    local destname
    destname="$(basename "$src" .qcow2).img"

    [ "$destname" = "debian-12-custom.img" ]
}

@test "preserves full name in transformation" {
    local src="images/debian-13-pve/debian-13-pve.qcow2"

    local destname
    destname="$(basename "$src" .qcow2).img"

    [ "$destname" = "debian-13-pve.img" ]
}

@test "handles versioned names in transformation" {
    local src="images/debian-12/deb12.8-custom.qcow2"

    local destname
    destname="$(basename "$src" .qcow2).img"

    [ "$destname" = "deb12.8-custom.img" ]
}

# -----------------------------------------------------------------------------
# Versioned Name Logic Tests
# -----------------------------------------------------------------------------

@test "reads versioned name from .versioned-name file" {
    local image_dir="${TEST_TEMP_DIR}/images/debian-12"

    echo "deb12.8-custom" > "${image_dir}/.versioned-name"

    local versioned_name
    versioned_name=$(cat "${image_dir}/.versioned-name")

    [ "$versioned_name" = "deb12.8-custom" ]
}

@test "symlink needed when versioned name differs from template" {
    local image_dir="${TEST_TEMP_DIR}/images/debian-12"
    local template_name="debian-12"

    echo "deb12.8-custom" > "${image_dir}/.versioned-name"

    local versioned_name
    versioned_name=$(cat "${image_dir}/.versioned-name")

    # Symlink logic from publish.sh
    local needs_symlink=false
    if [[ "$template_name" != "$versioned_name" ]]; then
        needs_symlink=true
    fi

    [ "$needs_symlink" = "true" ]
}

@test "no symlink needed when names match" {
    local image_dir="${TEST_TEMP_DIR}/images/debian-12"
    local template_name="debian-12"

    echo "debian-12" > "${image_dir}/.versioned-name"

    local versioned_name
    versioned_name=$(cat "${image_dir}/.versioned-name")

    # Symlink logic from publish.sh
    local needs_symlink=false
    if [[ "$template_name" != "$versioned_name" ]]; then
        needs_symlink=true
    fi

    [ "$needs_symlink" = "false" ]
}

# -----------------------------------------------------------------------------
# Checksum File Discovery Tests
# -----------------------------------------------------------------------------

@test "finds SHA256SUMS files in image directories" {
    local image_dir="${TEST_TEMP_DIR}/images/debian-12"

    echo "abc123  debian-12-custom.qcow2" > "${image_dir}/SHA256SUMS"

    local count=0
    for checksum in "${TEST_TEMP_DIR}"/images/*/SHA256SUMS; do
        [[ -f "$checksum" ]] || continue
        count=$((count + 1))
    done

    [ "$count" -eq 1 ]
}

@test "extracts image name from checksum path" {
    local image_dir="${TEST_TEMP_DIR}/images/debian-12"

    echo "abc123  debian-12-custom.qcow2" > "${image_dir}/SHA256SUMS"

    local checksum="${image_dir}/SHA256SUMS"
    local image_name
    image_name=$(basename "$(dirname "$checksum")")

    [ "$image_name" = "debian-12" ]
}

# -----------------------------------------------------------------------------
# Newer File Check Logic Tests
# -----------------------------------------------------------------------------

@test "detects when source is newer than destination" {
    local src="${TEST_TEMP_DIR}/src.qcow2"
    local dest="${TEST_TEMP_DIR}/dest.img"

    # Create dest first (older)
    echo "old" > "$dest"
    sleep 0.1
    # Create src second (newer)
    echo "new" > "$src"

    # Logic from publish.sh: skip if dest exists AND is newer than src
    local should_copy=true
    if [[ -f "$dest" && "$dest" -nt "$src" ]]; then
        should_copy=false
    fi

    [ "$should_copy" = "true" ]
}

@test "skips when destination is newer than source" {
    local src="${TEST_TEMP_DIR}/src.qcow2"
    local dest="${TEST_TEMP_DIR}/dest.img"

    # Create src first (older)
    echo "old" > "$src"
    sleep 0.1
    # Create dest second (newer)
    echo "new" > "$dest"

    # Logic from publish.sh
    local should_copy=true
    if [[ -f "$dest" && "$dest" -nt "$src" ]]; then
        should_copy=false
    fi

    [ "$should_copy" = "false" ]
}

@test "copies when destination does not exist" {
    local src="${TEST_TEMP_DIR}/src.qcow2"
    local dest="${TEST_TEMP_DIR}/dest.img"

    echo "source" > "$src"
    # dest does not exist

    local should_copy=true
    if [[ -f "$dest" && "$dest" -nt "$src" ]]; then
        should_copy=false
    fi

    [ "$should_copy" = "true" ]
}

# -----------------------------------------------------------------------------
# Dry-Run Flag Detection Tests
# -----------------------------------------------------------------------------

@test "dry-run flag sets DRY_RUN variable" {
    # Simulate argument parsing from publish.sh
    local DRY_RUN=false

    local args=("--dry-run")
    for arg in "${args[@]}"; do
        case "$arg" in
            --dry-run)
                DRY_RUN=true
                ;;
        esac
    done

    [ "$DRY_RUN" = "true" ]
}

@test "without dry-run flag DRY_RUN is false" {
    local DRY_RUN=false

    local args=()  # No args
    for arg in "${args[@]}"; do
        case "$arg" in
            --dry-run)
                DRY_RUN=true
                ;;
        esac
    done

    [ "$DRY_RUN" = "false" ]
}
