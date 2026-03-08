#!/usr/bin/env bats
#
# checksums.bats - Tests for checksums
#
# Tests:
# 1. Checksum generation for single files
# 2. Checksum verification
# 3. Multiple image handling
# 4. Per-image .sha256 file format
#

load 'test_helper/common'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# -----------------------------------------------------------------------------
# Checksum Generation Tests
# -----------------------------------------------------------------------------

@test "generates checksum for single image" {
    # Create mock image
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "debian-12-custom" 2048

    # Generate checksum manually (simulating checksums generate)
    (cd "${TEST_TEMP_DIR}/images/debian-12" && sha256sum "debian-12-custom.qcow2" > "debian-12-custom.qcow2.sha256")

    assert_file_exists "${TEST_TEMP_DIR}/images/debian-12/debian-12-custom.qcow2.sha256"
}

@test "generates checksums for multiple images" {
    # Create multiple mock images
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "debian-12-custom" 1024
    create_mock_image "${TEST_TEMP_DIR}/images/debian-13" "debian-13-custom" 1024

    # Generate checksums for both
    create_mock_checksum "${TEST_TEMP_DIR}/images/debian-12" "debian-12-custom"
    create_mock_checksum "${TEST_TEMP_DIR}/images/debian-13" "debian-13-custom"

    assert_file_exists "${TEST_TEMP_DIR}/images/debian-12/debian-12-custom.qcow2.sha256"
    assert_file_exists "${TEST_TEMP_DIR}/images/debian-13/debian-13-custom.qcow2.sha256"
}

@test "checksum file is alongside image file" {
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "test" 1024
    create_mock_checksum "${TEST_TEMP_DIR}/images/debian-12" "test"

    local image_dir
    image_dir=$(dirname "${TEST_TEMP_DIR}/images/debian-12/test.qcow2")
    local checksum_dir
    checksum_dir=$(dirname "${TEST_TEMP_DIR}/images/debian-12/test.qcow2.sha256")

    [ "$image_dir" = "$checksum_dir" ]
}

# -----------------------------------------------------------------------------
# Checksum Verification Tests
# -----------------------------------------------------------------------------

@test "verification passes for unchanged file" {
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "test" 1024
    create_mock_checksum "${TEST_TEMP_DIR}/images/debian-12" "test"

    # Verify
    run sh -c "cd ${TEST_TEMP_DIR}/images/debian-12 && sha256sum -c test.qcow2.sha256"
    [ "$status" -eq 0 ]
}

@test "verification fails for modified file" {
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "test" 1024
    create_mock_checksum "${TEST_TEMP_DIR}/images/debian-12" "test"

    # Modify the image
    echo "corrupted" >> "${TEST_TEMP_DIR}/images/debian-12/test.qcow2"

    # Verify should fail
    run sh -c "cd ${TEST_TEMP_DIR}/images/debian-12 && sha256sum -c test.qcow2.sha256"
    [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# Checksum Format Tests
# -----------------------------------------------------------------------------

@test "checksum format matches Debian convention" {
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "test" 1024
    create_mock_checksum "${TEST_TEMP_DIR}/images/debian-12" "test"

    # Format should be: <64-char-hash>  <filename>
    # Note: Two spaces between hash and filename (sha256sum default)
    local content
    content=$(cat "${TEST_TEMP_DIR}/images/debian-12/test.qcow2.sha256")

    # Extract hash (first field)
    local hash
    hash=$(echo "$content" | awk '{print $1}')
    [ "${#hash}" -eq 64 ]

    # Extract filename (second field)
    local filename
    filename=$(echo "$content" | awk '{print $2}')
    [ "$filename" = "test.qcow2" ]
}

@test "checksum hash is lowercase hex" {
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "test" 1024
    create_mock_checksum "${TEST_TEMP_DIR}/images/debian-12" "test"

    local hash
    hash=$(cat "${TEST_TEMP_DIR}/images/debian-12/test.qcow2.sha256" | awk '{print $1}')

    # Should only contain lowercase hex characters
    [[ "$hash" =~ ^[0-9a-f]+$ ]]
}

# -----------------------------------------------------------------------------
# Show Command Tests
# -----------------------------------------------------------------------------

@test "can display existing checksums" {
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "test" 1024
    create_mock_checksum "${TEST_TEMP_DIR}/images/debian-12" "test"

    # Simulate 'checksums show'
    run cat "${TEST_TEMP_DIR}/images/debian-12/test.qcow2.sha256"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test.qcow2"* ]]
}

# -----------------------------------------------------------------------------
# Edge Cases
# -----------------------------------------------------------------------------

@test "handles images with spaces in directory names" {
    local dir="${TEST_TEMP_DIR}/images/debian 12 test"
    mkdir -p "$dir"
    create_mock_image "$dir" "test" 1024

    # Generate checksum (must handle spaces properly)
    (cd "$dir" && sha256sum "test.qcow2" > "test.qcow2.sha256")

    assert_file_exists "$dir/test.qcow2.sha256"
}

@test "handles versioned image names" {
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "deb12.8-custom" 1024
    create_mock_checksum "${TEST_TEMP_DIR}/images/debian-12" "deb12.8-custom"

    assert_file_exists "${TEST_TEMP_DIR}/images/debian-12/deb12.8-custom.qcow2.sha256"
    assert_checksum_valid "${TEST_TEMP_DIR}/images/debian-12/deb12.8-custom.qcow2.sha256"
}
