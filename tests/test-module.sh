#!/bin/bash
set -euo pipefail

## @script Module Test Runner
## @brief Run individual module tests in isolation
## @description Allows testing a single module without running full orchestrator

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <module-name>" >&2
    echo "Example: $0 3dprinter" >&2
    exit 1
fi

MODULE="$1"
MODULE_FILE="../lib/${MODULE}.sh"

if [[ ! -f "$MODULE_FILE" ]]; then
    echo "ERROR: Module file not found: $MODULE_FILE" >&2
    exit 1
fi

# Source core functions
# shellcheck source=/dev/null
source "../lib/core.sh" 2>/dev/null || {
    echo "ERROR: core.sh not found" >&2
    exit 1
}

# Load test config
if [[ -f "test-config.yml" ]]; then
    core::load_config "test-config.yml"
elif [[ -f "../config.yml.example" ]]; then
    core::load_config "../config.yml.example"
else
    echo "ERROR: No config file found" >&2
    exit 1
fi

# Source the module
# shellcheck source=/dev/null
source "$MODULE_FILE"

# Find and run the configure function
FUNC="${MODULE}::configure"
if ! declare -f "$FUNC" >/dev/null 2>&1; then
    echo "ERROR: Function $FUNC not found in $MODULE_FILE" >&2
    exit 1
fi

# Ensure state directory
mkdir -p /var/lib/rpi-config/state

echo "=== Testing module: $MODULE ==="
"$FUNC"
echo "=== Test complete ==="
