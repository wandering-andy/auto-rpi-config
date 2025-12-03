#!/bin/bash
set -euo pipefail

# Integration test runner
# Runs inside Docker/Podman container

# Fix SC2155: Separate declaration from assignment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ROOT_DIR

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

## @fn run_test
## @brief Run a single test script
run_test() {
    local test_script="$1"
    local test_name
    test_name="$(basename "$test_script" .sh)"
    
    echo "Running: $test_name"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if bash "$test_script"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "✓ PASS: $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "✗ FAIL: $test_name"
    fi
}

main() {
    echo "=== Integration Test Runner ==="
    echo "Working directory: $ROOT_DIR"
    echo
    
    # Find and run all test scripts
    local test_scripts=()
    mapfile -t test_scripts < <(find "$SCRIPT_DIR" -maxdepth 1 -type f -name 'test-*.sh' | sort)
    
    for test in "${test_scripts[@]}"; do
        run_test "$test"
    done
    
    echo
    echo "=== Test Summary ==="
    echo "Total:  $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    [[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
}

main "$@"
