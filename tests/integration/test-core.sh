#!/bin/bash
set -euo pipefail

# Test core module functionality

# Fix SC2155: Separate declaration from assignment
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR

# Source core module
# shellcheck source=../../lib/core.sh
source "${ROOT_DIR}/lib/core.sh" 2>/dev/null || {
    echo "ERROR: Failed to source core.sh"
    exit 1
}

test_yq_install() {
    echo "  Testing yq installation..."
    core::install_yq || return 1
    command -v yq >/dev/null || return 1
}

test_config_load() {
    echo "  Testing config loading..."
    cp "${ROOT_DIR}/tests/fixtures/minimal.yml" "${ROOT_DIR}/config.yml"
    core::load_config || return 1
    [[ "${CONFIG[hostname]}" == "test-pi" ]] || return 1
    rm -f "${ROOT_DIR}/config.yml"
}

main() {
    echo "Testing core module..."
    
    test_yq_install || { echo "FAIL: yq install"; exit 1; }
    test_config_load || { echo "FAIL: config load"; exit 1; }
    
    echo "All core tests passed"
}

main "$@"
