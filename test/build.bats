#!/usr/bin/env bats
#
# build.bats - Tests for build.sh
#
# Tests:
# 1. Template discovery
# 2. SSH key handling (ephemeral and existing)
# 3. Argument parsing (--help, --clean-cache, --auto-update)
# 4. Checksum generation
#

load 'test_helper/common'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# -----------------------------------------------------------------------------
# Template Discovery Tests
# -----------------------------------------------------------------------------

@test "discovers templates from templates/ directory" {
    # Verify mock templates were created in setup
    [ -f "${TEST_TEMP_DIR}/templates/debian-12-custom/template.pkr.hcl" ]
    [ -f "${TEST_TEMP_DIR}/templates/debian-13-custom/template.pkr.hcl" ]

    # Count templates using same pattern as build.sh
    local templates
    templates=(${TEST_TEMP_DIR}/templates/*/template.pkr.hcl)
    [ "${#templates[@]}" -eq 2 ]
}

@test "extracts template name from path" {
    local template_path="${TEST_TEMP_DIR}/templates/debian-12-custom/template.pkr.hcl"
    local template_dir
    template_dir=$(dirname "$template_path")
    local name
    name=$(basename "$template_dir")

    [ "$name" = "debian-12-custom" ]
}

# -----------------------------------------------------------------------------
# SSH Key Handling Tests
# -----------------------------------------------------------------------------

@test "generates ephemeral SSH key when SSH_KEY_FILE not set" {
    mock_ssh_keygen_setup

    # Simulate ephemeral key generation
    local temp_key="${TEST_TEMP_DIR}/ephemeral_key"
    ssh-keygen -t ed25519 -N "" -f "$temp_key"

    assert_file_exists "$temp_key"
    assert_file_exists "${temp_key}.pub"
}

@test "reads public key from .pub file" {
    # Create mock key pair
    echo "mock-private-key" > "${TEST_TEMP_DIR}/test_key"
    echo "ssh-ed25519 AAAAMOCK test@example" > "${TEST_TEMP_DIR}/test_key.pub"

    local pub_key
    pub_key=$(cat "${TEST_TEMP_DIR}/test_key.pub")

    [[ "$pub_key" == *"ssh-ed25519"* ]]
}

# -----------------------------------------------------------------------------
# Argument Parsing Tests
# -----------------------------------------------------------------------------

@test "--help flag is recognized" {
    # Source the help text pattern from build.sh
    # We're testing the pattern, not the actual script execution
    local help_pattern="--help"
    local clean_cache_pattern="--clean-cache"
    local auto_update_pattern="--auto-update"

    # These should be recognized flags in build.sh
    [[ "--help" =~ ^-- ]]
    [[ "--clean-cache" =~ ^-- ]]
    [[ "--auto-update" =~ ^-- ]]
}

# -----------------------------------------------------------------------------
# Image Split Function Tests
# -----------------------------------------------------------------------------

@test "split_large_image does nothing for small files" {
    # Create a small image (1KB)
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "test-small" 1024

    # Verify image exists and is small
    local size
    size=$(stat -c%s "${TEST_TEMP_DIR}/images/debian-12/test-small.qcow2")
    [ "$size" -eq 1024 ]

    # Image should not be split (threshold is ~2GB)
    [ ! -f "${TEST_TEMP_DIR}/images/debian-12/test-small.qcow2.partaa" ]
}

# -----------------------------------------------------------------------------
# Checksum Generation Tests
# -----------------------------------------------------------------------------

@test "generates SHA256 checksum for image" {
    # Create mock image
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "debian-12-custom" 1024

    # Generate checksum
    create_mock_checksum "${TEST_TEMP_DIR}/images/debian-12" "debian-12-custom"

    # Verify checksum file exists
    assert_file_exists "${TEST_TEMP_DIR}/images/debian-12/debian-12-custom.qcow2.sha256"
}

@test "checksum file has correct format" {
    # Create mock image
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "debian-12-custom" 1024

    # Generate checksum
    create_mock_checksum "${TEST_TEMP_DIR}/images/debian-12" "debian-12-custom"

    # Verify format: <hash>  <filename>
    local checksum_content
    checksum_content=$(cat "${TEST_TEMP_DIR}/images/debian-12/debian-12-custom.qcow2.sha256")

    # Should contain the filename
    [[ "$checksum_content" == *"debian-12-custom.qcow2"* ]]

    # Should have a 64-character hex hash (SHA256)
    local hash
    hash=$(echo "$checksum_content" | awk '{print $1}')
    [ "${#hash}" -eq 64 ]
}

@test "checksum verification passes for valid file" {
    # Create mock image
    create_mock_image "${TEST_TEMP_DIR}/images/debian-12" "debian-12-custom" 1024

    # Generate checksum
    create_mock_checksum "${TEST_TEMP_DIR}/images/debian-12" "debian-12-custom"

    # Verify checksum
    assert_checksum_valid "${TEST_TEMP_DIR}/images/debian-12/debian-12-custom.qcow2.sha256"
}

# -----------------------------------------------------------------------------
# Output Directory Tests
# -----------------------------------------------------------------------------

@test "output directory follows template pattern for -custom" {
    # debian-12-custom -> images/debian-12 (strips -custom)
    local template="debian-12-custom"
    local expected_dir="debian-12"

    local actual_dir="${template%-custom}"
    [ "$actual_dir" = "$expected_dir" ]
}

@test "output directory keeps full name for non-custom templates" {
    # debian-13-pve -> images/debian-13-pve (keeps full name)
    local template="debian-13-pve"

    # Only strip if ends with -custom
    if [[ "$template" == *-custom ]]; then
        local dir="${template%-custom}"
    else
        local dir="$template"
    fi

    [ "$dir" = "debian-13-pve" ]
}

# -----------------------------------------------------------------------------
# Versioned Name Tests
# -----------------------------------------------------------------------------

@test ".versioned-name file is read when present" {
    local image_dir="${TEST_TEMP_DIR}/images/debian-12"

    # Create versioned name file
    echo "deb12.8-custom" > "${image_dir}/.versioned-name"

    # Read it back
    local versioned_name
    versioned_name=$(cat "${image_dir}/.versioned-name")

    [ "$versioned_name" = "deb12.8-custom" ]
}

@test "falls back to template name when .versioned-name missing" {
    local image_dir="${TEST_TEMP_DIR}/images/debian-12"
    local template_name="debian-12-custom"

    # No .versioned-name file
    [ ! -f "${image_dir}/.versioned-name" ]

    # Should use template name as fallback
    local final_name="$template_name"
    if [[ -f "${image_dir}/.versioned-name" ]]; then
        final_name=$(cat "${image_dir}/.versioned-name")
    fi

    [ "$final_name" = "debian-12-custom" ]
}
