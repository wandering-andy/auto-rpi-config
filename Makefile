SHELL := /bin/bash

.PHONY: help lint test test-module docs install permissions clean

# Default target
help:
	@echo "Raspberry Pi Configuration - Development Commands"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  lint         - Run ShellCheck on all scripts"
	@echo "  test         - Run integration tests and config validation"
	@echo "  test-module  - Test individual module (usage: make test-module MODULE=3dprinter)"
	@echo "  docs         - Generate README from script comments"
	@echo "  permissions   - Set correct file permissions"
	@echo "  install      - Install to /opt/auto-rpi-config"
	@echo "  clean        - Remove generated files and state"

# Ensure scripts have the correct permissions
permissions:
	@echo "Setting executable permissions..."
	@chmod +x auto-rpi-config.sh
	@chmod +x health-check.sh
	@chmod +x tests/validate-config.sh
	@chmod +x tests/test-module.sh
	@find lib -type f -name "*.sh" -exec chmod +x {} \;
	@echo "✓ Permissions set"

# Run shellcheck linter
lint: permissions
	@echo "Running ShellCheck..."
	@shellcheck -x auto-rpi-config.sh health-check.sh tests/*.sh lib/*.sh 2>&1 || true

# Run tests in Docker
test: permissions
	@echo "Running validation tests..."
	@./tests/validate-config.sh config.yml.example

# Test individual module
test-module: permissions
	@if [ -z "$(MODULE)" ]; then \
		echo "ERROR: MODULE not specified. Usage: make test-module MODULE=3dprinter" >&2; \
		exit 1; \
	fi
	@echo "Testing module: $(MODULE)"
	@cd tests && ./test-module.sh $(MODULE)

# Generate documentation
docs: permissions
	@echo "Generating documentation..."
	@if [ -f scripts/generate-docs.sh ]; then \
		bash scripts/generate-docs.sh; \
	else \
		echo "ERROR: scripts/generate-docs.sh not found" >&2; \
		exit 1; \
	fi
	@echo "✓ Documentation generated"

# Install required tools
install: permissions
	@echo "Installing to /opt/auto-rpi-config..."
	@mkdir -p /opt/auto-rpi-config
	@cp -r . /opt/auto-rpi-config/
	@ln -sf /opt/auto-rpi-config/auto-rpi-config.sh /usr/local/bin/auto-rpi-config
	@ln -sf /opt/auto-rpi-config/health-check.sh /usr/local/bin/rpi-health
	@echo "✓ Installed to /opt/auto-rpi-config"

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	@rm -f /tmp/yq
	@rm -rf /var/lib/rpi-config/state/*
