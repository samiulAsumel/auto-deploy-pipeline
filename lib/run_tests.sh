#!/usr/bin/env bash
# lib/run_tests.sh — Test Suite Runner  v1.0.0
# Sourced by deploy.sh.
# Provides: module_run_tests
# Runs the configured test command in the new release directory.
# Returns 0 on pass, 1 on failure (deploy will abort before any switch).
# set -euo pipefail is inherited from the orchestrator.

module_run_tests() {
    local test_cmd="${TEST_CMD:-npm test}"
    local test_timeout="${TEST_TIMEOUT:-300}"

    if $DRY_RUN; then
        log "INFO" "TESTS" "[DRY-RUN] Would run: ${test_cmd} (timeout: ${test_timeout}s)"
        return 0
    fi

    log "INFO" "TESTS" "Running test suite: ${test_cmd}"
    log "INFO" "TESTS" "Timeout: ${test_timeout}s  Directory: ${RELEASE_DIR}"

    cd "$RELEASE_DIR"

    local test_start; test_start=$(date +%s)
    local test_exit=0

    # Run tests under a timeout; capture output to both log and console
    if command -v timeout &>/dev/null; then
        timeout "$test_timeout" bash -c "$test_cmd" 2>&1 \
            | while IFS= read -r line; do log "INFO" "TESTS" "$line"; done
        test_exit=${PIPESTATUS[0]}
    else
        eval "$test_cmd" 2>&1 \
            | while IFS= read -r line; do log "INFO" "TESTS" "$line"; done
        test_exit=${PIPESTATUS[0]}
    fi

    local test_end; test_end=$(date +%s)
    local test_duration=$(( test_end - test_start ))

    # timeout exits 124 when the time limit is hit
    if [[ "$test_exit" -eq 124 ]]; then
        log "ERROR" "TESTS" "Test suite timed out after ${test_timeout}s"
        return 1
    fi

    if [[ "$test_exit" -ne 0 ]]; then
        log "ERROR" "TESTS" "Tests FAILED (exit ${test_exit}) in ${test_duration}s"
        return 1
    fi

    log "OK" "TESTS" "Tests PASSED in ${test_duration}s"
    return 0
}
