# packer Makefile

.PHONY: help install-deps

help:
	@echo "packer - Debian cloud image templates"
	@echo ""
	@echo "Targets:"
	@echo "  make install-deps  - Install packer"
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
