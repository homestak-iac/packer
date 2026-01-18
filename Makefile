# packer Makefile

.PHONY: help install-deps test lint

help:
	@echo "packer - Debian cloud image templates"
	@echo ""
	@echo "Targets:"
	@echo "  make install-deps  - Install packer"
	@echo "  make test          - Run bats tests"
	@echo "  make lint          - Run shellcheck on scripts"
	@echo ""
	@echo "Build images via iac-driver:"
	@echo "  ./run.sh --scenario packer-build-fetch --remote <build-host>"

install-deps:
	@echo "Installing packer..."
	@if ! command -v packer >/dev/null 2>&1; then \
		echo "Packer not found. Install from: https://developer.hashicorp.com/packer/install"; \
		exit 1; \
	fi
	@echo "packer installed: $$(packer version)"

test:
	@echo "Running bats tests..."
	@if ! command -v bats >/dev/null 2>&1; then \
		echo "bats not found. Install with: apt install bats"; \
		exit 1; \
	fi
	bats test/

lint:
	@echo "Running shellcheck..."
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "shellcheck not found. Install with: apt install shellcheck"; \
		exit 1; \
	fi
	shellcheck build.sh publish.sh checksums.sh
