#!/usr/bin/env bash
# tests/test_deploy.sh — Unit tests for deploy modules  v1.0.0
# Usage: bash tests/test_deploy.sh
# All tests run in a temp directory; no real servers or repos are touched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; SKIP=0

# ── Test framework ────────────────────────────────────────────────────────────
assert_eq()  { [[ "$1" == "$2" ]] && { echo "  PASS: $3"; (( ++PASS )); } || { echo "  FAIL: $3 (got '$1', want '$2')"; (( ++FAIL )); }; true; }
assert_0()   { "$@" && { echo "  PASS: $* exits 0"; (( ++PASS )); } || { echo "  FAIL: $* exited non-zero"; (( ++FAIL )); }; true; }
assert_fail(){ "$@" && { echo "  FAIL: $* should have failed"; (( ++FAIL )); } || { echo "  PASS: $* correctly failed"; (( ++PASS )); }; true; }

# ── Setup temp environment ────────────────────────────────────────────────────
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

export RELEASES_DIR="${TMPDIR_TEST}/releases"
export CURRENT_LINK="${TMPDIR_TEST}/current"
export SHARED_DIR="${TMPDIR_TEST}/shared"
export LOG_DIR="${TMPDIR_TEST}/logs"
export STATE_DIR="${TMPDIR_TEST}/state"
export ROLLBACK_STATE_FILE="${TMPDIR_TEST}/deploy_previous"
export APP_NAME="testapp"
export APP_USER="$(whoami)"
export APP_GROUP="$(whoami)"
export APP_TYPE="static"
export REPO_URL="file:///dev/null"
export BRANCH="main"
export HEALTH_URL=""
export WEBSERVER="none"
export APP_SERVER="none"
export NOTIFY_METHOD="none"
export DEPLOY_BASE="$TMPDIR_TEST"
export DRY_RUN=false
export VERBOSE=false
export DEPLOY_ID="20260530-120000"
export RELEASE_DIR="${RELEASES_DIR}/${DEPLOY_ID}"
export ENVIRONMENT="test"
export DEPLOY_USER="testuser"
export DEPLOY_SWITCHED=false
export VERSION="1.0.0"
export MIN_DISK_MB=1
export CHECK_DB=false
export RUN_TESTS=false
export BUILD_ENABLED=false
export AUTO_ROLLBACK=false
export KEEP_RELEASES=5
export HEALTH_RETRIES=1
export HEALTH_RETRY_INTERVAL=1
export HEALTH_WARMUP=0

mkdir -p "$RELEASES_DIR" "$SHARED_DIR" "$LOG_DIR" "$STATE_DIR"
touch "${LOG_DIR}/${DEPLOY_ID}.log"

# Minimal log function for modules
log() { local lvl="$1" mod="$2" msg="$3"; echo "[${lvl}] [${mod}] ${msg}" >> "${LOG_DIR}/${DEPLOY_ID}.log"; }
export -f log

# Source all modules (sourcing only — not running main)
for mod in backup_current switch_version verify_deploy rollback; do
    # shellcheck disable=SC1090
    source "${SCRIPT_DIR}/lib/${mod}.sh"
done

# Also source restart_services and notify_deploy (needed by rollback)
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/restart_services.sh"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/notify_deploy.sh"

echo ""
echo "═══════════════════════════════════════"
echo "  auto-deploy-pipeline — Unit Tests"
echo "═══════════════════════════════════════"
echo ""

# ────────────────────────────────────────────────────────────────────────────
echo "── backup_current ──"

# Test: first deploy (no symlink)
[[ -L "$CURRENT_LINK" ]] && rm -f "$CURRENT_LINK"
module_backup_current
state=$(cat "$ROLLBACK_STATE_FILE" 2>/dev/null || true)
assert_eq "" "$state" "first deploy writes empty state file"

# Test: existing symlink is recorded
mkdir -p "${RELEASES_DIR}/20260529-100000"
ln -sfn "${RELEASES_DIR}/20260529-100000" "$CURRENT_LINK"
module_backup_current
state=$(cat "$ROLLBACK_STATE_FILE" 2>/dev/null | tr -d '[:space:]' || true)
assert_eq "${RELEASES_DIR}/20260529-100000" "$state" "records previous release path"
rm -f "$CURRENT_LINK"

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "── switch_version ──"

mkdir -p "$RELEASE_DIR"
module_switch_version
resolved=$(readlink "$CURRENT_LINK" 2>/dev/null || true)
assert_eq "$RELEASE_DIR" "$resolved" "symlink points to RELEASE_DIR"

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "── verify_deploy (HEALTH_URL empty → skip) ──"

export HEALTH_URL=""
assert_0 module_verify_deploy

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "── verify_deploy (HTTP 200 mock) ──"

# Start a tiny HTTP server to return 200
if command -v python3 &>/dev/null; then
    python3 -m http.server 18999 --directory "$TMPDIR_TEST" &>/dev/null &
    HTTP_PID=$!
    sleep 1
    export HEALTH_URL="http://localhost:18999/"
    assert_0 module_verify_deploy
    kill "$HTTP_PID" 2>/dev/null || true
    export HEALTH_URL=""
else
    echo "  SKIP: python3 not found — HTTP mock test skipped"
    (( SKIP++ ))
fi

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "── rollback ──"

# Setup: record a previous release and a current link
PREV_RELEASE="${RELEASES_DIR}/20260529-100000"
mkdir -p "$PREV_RELEASE"
echo "$PREV_RELEASE" > "$ROLLBACK_STATE_FILE"
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"

module_rollback "unit-test"
resolved=$(readlink "$CURRENT_LINK" 2>/dev/null || true)
assert_eq "$PREV_RELEASE" "$resolved" "rollback restores previous symlink"

# ── rollback with no state file ───────────────────────────────────────────
rm -f "$ROLLBACK_STATE_FILE"
assert_fail module_rollback "no-state"

# ── rollback with empty state ─────────────────────────────────────────────
echo "" > "$ROLLBACK_STATE_FILE"
assert_fail module_rollback "empty-state"

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "── notify_deploy (NOTIFY_METHOD=none) ──"

export NOTIFY_METHOD="none"
assert_0 _notify_deploy "success" "test message"

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
printf "  PASSED: %d   FAILED: %d   SKIPPED: %d\n" "$PASS" "$FAIL" "$SKIP"
echo "═══════════════════════════════════════"
echo ""

(( FAIL == 0 )) && exit 0 || exit 1
