#!/usr/bin/env bash
#
# common.bash - Shared test helper for packer bats tests
#
# Provides:
# - Test environment setup/teardown
# - Mock functions for packer, SSH key generation
# - File structure helpers
# - Common assertions
#

# -----------------------------------------------------------------------------
# Test Environment
# -----------------------------------------------------------------------------

# Temporary directory for test artifacts
TEST_TEMP_DIR=""

# Path to scripts under test (relative to test directory)
PACKER_DIR="${BATS_TEST_DIRNAME}/.."

setup_test_env() {
    # Create isolated temp directory for each test
    TEST_TEMP_DIR="$(mktemp -d)"

    # Create mock packer directory structure
    mkdir -p "${TEST_TEMP_DIR}/templates/debian-12-custom"
    mkdir -p "${TEST_TEMP_DIR}/templates/debian-13-custom"
    mkdir -p "${TEST_TEMP_DIR}/images/debian-12"
    mkdir -p "${TEST_TEMP_DIR}/images/debian-13"
    mkdir -p "${TEST_TEMP_DIR}/cache"
    mkdir -p "${TEST_TEMP_DIR}/logs"

    # Create mock template files
    cat > "${TEST_TEMP_DIR}/templates/debian-12-custom/template.pkr.hcl" << 'EOF'
variable "ssh_public_key" { type = string }
variable "ssh_private_key_file" { type = string }

source "qemu" "debian" {
  iso_url = "https://cloud.debian.org/debian-12.qcow2"
  output_directory = "../../images/debian-12"
}

build {
  sources = ["source.qemu.debian"]
}
EOF

    cat > "${TEST_TEMP_DIR}/templates/debian-13-custom/template.pkr.hcl" << 'EOF'
variable "ssh_public_key" { type = string }
variable "ssh_private_key_file" { type = string }

source "qemu" "debian" {
  iso_url = "https://cloud.debian.org/debian-13.qcow2"
  output_directory = "../../images/debian-13"
}

build {
  sources = ["source.qemu.debian"]
}
EOF

    export TEST_TEMP_DIR
}

teardown_test_env() {
    if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# -----------------------------------------------------------------------------
# Mock Functions
# -----------------------------------------------------------------------------

# Mock packer command
MOCK_PACKER_CALLS=()
MOCK_PACKER_EXIT_CODE=0

mock_packer_setup() {
    MOCK_PACKER_CALLS=()
    MOCK_PACKER_EXIT_CODE=0

    packer() {
        MOCK_PACKER_CALLS+=("$*")
        return "$MOCK_PACKER_EXIT_CODE"
    }
    export -f packer
}

mock_packer_set_exit_code() {
    MOCK_PACKER_EXIT_CODE="$1"
}

mock_packer_assert_called_with() {
    local expected="$1"
    local found=false

    for call in "${MOCK_PACKER_CALLS[@]}"; do
        if [[ "$call" == *"$expected"* ]]; then
            found=true
            break
        fi
    done

    if [[ "$found" != "true" ]]; then
        echo "Expected packer to be called with: $expected"
        echo "Actual calls:"
        printf '  %s\n' "${MOCK_PACKER_CALLS[@]}"
        return 1
    fi
}

# Mock ssh-keygen for ephemeral key generation
mock_ssh_keygen_setup() {
    ssh-keygen() {
        local output_file=""
        local args=("$@")

        # Parse args to find -f flag
        for ((i=0; i<${#args[@]}; i++)); do
            if [[ "${args[$i]}" == "-f" ]]; then
                output_file="${args[$((i+1))]}"
                break
            fi
        done

        if [[ -n "$output_file" ]]; then
            # Create mock key files
            echo "mock-private-key" > "$output_file"
            echo "ssh-ed25519 AAAAMOCK user@test" > "${output_file}.pub"
        fi
        return 0
    }
    export -f ssh-keygen
}

# -----------------------------------------------------------------------------
# File Helpers
# -----------------------------------------------------------------------------

create_mock_image() {
    local dir="$1"
    local name="$2"
    local size="${3:-1024}"  # Default 1KB

    mkdir -p "$dir"
    dd if=/dev/zero of="${dir}/${name}.qcow2" bs=1 count="$size" 2>/dev/null
}

create_large_mock_image() {
    local dir="$1"
    local name="$2"
    local size_mb="${3:-10}"  # Default 10MB for testing

    mkdir -p "$dir"
    dd if=/dev/zero of="${dir}/${name}.qcow2" bs=1M count="$size_mb" 2>/dev/null
}

create_mock_checksum() {
    local dir="$1"
    local name="$2"

    if [[ -f "${dir}/${name}.qcow2" ]]; then
        (cd "$dir" && sha256sum "${name}.qcow2" > "${name}.qcow2.sha256")
    fi
}

# -----------------------------------------------------------------------------
# Assertions
# -----------------------------------------------------------------------------

assert_file_exists() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "Expected file to exist: $file"
        return 1
    fi
}

assert_file_not_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        echo "Expected file NOT to exist: $file"
        return 1
    fi
}

assert_dir_exists() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo "Expected directory to exist: $dir"
        return 1
    fi
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"

    if ! grep -q "$pattern" "$file"; then
        echo "Expected file $file to contain: $pattern"
        echo "Actual content:"
        cat "$file"
        return 1
    fi
}

assert_output_contains() {
    local expected="$1"

    if [[ "$output" != *"$expected"* ]]; then
        echo "Expected output to contain: $expected"
        echo "Actual output: $output"
        return 1
    fi
}

assert_output_not_contains() {
    local unexpected="$1"

    if [[ "$output" == *"$unexpected"* ]]; then
        echo "Expected output NOT to contain: $unexpected"
        echo "Actual output: $output"
        return 1
    fi
}

assert_checksum_valid() {
    local checksum_file="$1"
    local dir
    dir=$(dirname "$checksum_file")

    if ! (cd "$dir" && sha256sum -c "$(basename "$checksum_file")" > /dev/null 2>&1); then
        echo "Checksum verification failed for: $checksum_file"
        return 1
    fi
}
