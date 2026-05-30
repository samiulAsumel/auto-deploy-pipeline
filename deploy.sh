#!/usr/bin/env bash
# deploy.sh — Automated Deployment Pipeline  Orchestrator v1.0.0
# Pulls latest code, runs tests, backs up, deploys atomically, verifies, notifies.
# Auto-rolls back to previous release if health check fails after deploy.
# Usage: ./deploy.sh <environment> [--dry-run] [--verbose] [--skip-tests] [--rollback]
#        ./deploy.sh production
#        ./deploy.sh staging --dry-run --verbose
#        ./deploy.sh production --rollback
# Supports: Node.js | Python | PHP | Static sites
# RHEL 9 / Ubuntu Server
set -euo pipefail
trap '_on_error $LINENO "$BASH_COMMAND"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Error handler ─────────────────────────────────────────────────────────────
_on_error() {
    local line="$1" cmd="$2"
    log "ERROR" "DEPLOY" "Fatal error at line ${line}: ${cmd}"
    # Only auto-rollback if we've already switched versions (DEPLOY_SWITCHED is set)
    if [[ "${DEPLOY_SWITCHED:-false}" == "true" ]] && [[ "${AUTO_ROLLBACK:-true}" == "true" ]]; then
        log "WARN" "DEPLOY" "Triggering auto-rollback due to error..."
        _do_rollback "error: ${cmd}" || true
    fi
    _notify_deploy "failure" "Deploy failed at line ${line}: ${cmd}" || true
    release_lock || true
    exit 1
}

# ── Parse arguments ───────────────────────────────────────────────────────────
ENVIRONMENT="${1:-}"
DRY_RUN=false; VERBOSE=false; SKIP_TESTS=false; DO_ROLLBACK=false

[[ -z "$ENVIRONMENT" ]] && {
    echo "Usage: $0 <environment> [--dry-run] [--verbose] [--skip-tests] [--rollback]" >&2
    echo "  Environments: production | staging | dev" >&2
    exit 1
}

shift
for _arg in "$@"; do
    case "$_arg" in
        --dry-run)     DRY_RUN=true    ;;
        --verbose)     VERBOSE=true    ;;
        --skip-tests)  SKIP_TESTS=true ;;
        --rollback)    DO_ROLLBACK=true ;;
        --*)           echo "[WARN] Unknown flag: ${_arg}" >&2 ;;
    esac
done

# ── Load configuration ────────────────────────────────────────────────────────
CONFIG_FILE="${SCRIPT_DIR}/config.conf"
[[ -f "$CONFIG_FILE" ]] || { echo "[FATAL] config.conf not found: ${CONFIG_FILE}" >&2; exit 1; }
# shellcheck source=config.conf
source "$CONFIG_FILE"

ENV_CONFIG="${SCRIPT_DIR}/config.${ENVIRONMENT}.conf"
if [[ -f "$ENV_CONFIG" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_CONFIG"
else
    echo "[WARN] No environment config found: ${ENV_CONFIG} — using config.conf defaults" >&2
fi

# ── Source library modules ────────────────────────────────────────────────────
for _mod in pre_deploy backup_current pull_code run_tests switch_version \
            restart_services verify_deploy rollback notify_deploy; do
    _path="${SCRIPT_DIR}/lib/${_mod}.sh"
    [[ -f "$_path" ]] || { echo "[FATAL] Module missing: ${_path}" >&2; exit 1; }
    # shellcheck disable=SC1090
    source "$_path"
done

# ── Deploy ID and paths ───────────────────────────────────────────────────────
DEPLOY_ID=$(date +%Y%m%d-%H%M%S)
RELEASE_DIR="${RELEASES_DIR}/${DEPLOY_ID}"
LOG_FILE="${LOG_DIR}/${DEPLOY_ID}.log"
DEPLOY_SWITCHED=false
DEPLOY_USER="${SUDO_USER:-$(whoami)}"

# ── Colours ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
    MAGENTA='\033[0;35m'; DIM='\033[2m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; BOLD=''; RESET=''
    MAGENTA=''; DIM=''
fi

# ── Logging ───────────────────────────────────────────────────────────────────
$DRY_RUN || {
    mkdir -p "$LOG_DIR" "$STATE_DIR"
    chmod 750 "$STATE_DIR"
}

_sev_colour() {
    case "${1^^}" in
        ERROR|FAIL) echo "$RED"    ;;
        WARN)       echo "$YELLOW" ;;
        OK|SUCCESS) echo "$GREEN"  ;;
        STEP)       echo "$CYAN"   ;;
        *)          echo "$RESET"  ;;
    esac
}

log() {
    local level="$1" module="$2" msg="$3"
    local ts entry colour
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    entry="[${ts}] [${module}] [${level}] ${msg}"
    $DRY_RUN || echo "$entry" >> "$LOG_FILE"
    if [[ -t 1 ]] || $VERBOSE; then
        colour=$(_sev_colour "$level")
        echo -e "${colour}${entry}${RESET}"
    fi
}

step() {
    local num="$1" title="$2"
    log "STEP" "DEPLOY" "━━━ Step ${num}: ${title} ━━━"
    [[ -t 1 ]] && echo ""
}

# ── Lock file ─────────────────────────────────────────────────────────────────
acquire_lock() {
    $DRY_RUN || mkdir -p "$(dirname "$LOCK_FILE")"
    if [[ -f "$LOCK_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo 0)
        if kill -0 "$old_pid" 2>/dev/null; then
            log "ERROR" "LOCK" "Another deploy running (PID ${old_pid}) — aborting"
            exit 1
        fi
        log "WARN" "LOCK" "Stale lock from PID ${old_pid} — removing"
        $DRY_RUN || rm -f "$LOCK_FILE"
    fi
    $DRY_RUN || echo $$ > "$LOCK_FILE"
    log "OK" "LOCK" "Acquired lock (PID $$)"
}

release_lock() { $DRY_RUN || rm -f "${LOCK_FILE:-}"; }
trap 'release_lock' EXIT

# ── Rollback wrapper ──────────────────────────────────────────────────────────
_do_rollback() {
    local reason="${1:-manual}"
    log "WARN" "DEPLOY" "⚠  ROLLBACK triggered — reason: ${reason}"
    module_rollback "$reason" && return 0 || return 1
}

# ════════════════════════════════════════════════════════════════════════════
# LIBRARY BOUNDARY — stop here when sourced (e.g., by tests)
# ════════════════════════════════════════════════════════════════════════════
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

# ════════════════════════════════════════════════════════════════════════════
# BANNER
# ════════════════════════════════════════════════════════════════════════════
if [[ -t 1 ]] || $VERBOSE; then
    echo -e "${BOLD}${CYAN}"
    cat <<'BANNER'
╔══════════════════════════════════════════════════════════════════╗
║    Automated Deployment Pipeline  —  v1.0.0                      ║
║    RHEL 9 / Ubuntu Server  ·  Node.js · Python · PHP · Static    ║
╚══════════════════════════════════════════════════════════════════╝
BANNER
    echo -e "${RESET}"
fi

log "INFO" "DEPLOY" "Deploy ${DEPLOY_ID} started — env=${ENVIRONMENT} app=${APP_NAME} user=${DEPLOY_USER}"
$DRY_RUN && log "WARN" "DEPLOY" "DRY-RUN mode — no changes will be made"

# ── Rotate old logs ───────────────────────────────────────────────────────────
$DRY_RUN || find "$LOG_DIR" -name "*.log" -mtime +"${LOG_MAX_DAYS:-30}" -delete 2>/dev/null || true

acquire_lock

DEPLOY_START=$(date +%s)

# ════════════════════════════════════════════════════════════════════════════
# ROLLBACK-ONLY MODE  (--rollback flag)
# ════════════════════════════════════════════════════════════════════════════
if $DO_ROLLBACK; then
    log "INFO" "DEPLOY" "Manual rollback requested"
    _do_rollback "manual"
    _notify_deploy "rollback" "Manual rollback executed on ${ENVIRONMENT} by ${DEPLOY_USER}"
    log "OK" "DEPLOY" "Rollback complete"
    exit 0
fi

# ════════════════════════════════════════════════════════════════════════════
# STEP 1 — PRE-FLIGHT CHECKS
# ════════════════════════════════════════════════════════════════════════════
step 1 "PRE-FLIGHT CHECKS"
module_pre_deploy

# ════════════════════════════════════════════════════════════════════════════
# STEP 2 — BACKUP CURRENT VERSION
# ════════════════════════════════════════════════════════════════════════════
step 2 "BACKUP CURRENT VERSION"
module_backup_current

# ════════════════════════════════════════════════════════════════════════════
# STEP 3 — PULL CODE & INSTALL DEPENDENCIES
# ════════════════════════════════════════════════════════════════════════════
step 3 "PULL CODE"
module_pull_code

# ════════════════════════════════════════════════════════════════════════════
# STEP 4 — RUN TESTS (optional)
# ════════════════════════════════════════════════════════════════════════════
if [[ "${RUN_TESTS:-true}" == "true" ]] && ! $SKIP_TESTS; then
    step 4 "RUN TESTS"
    if ! module_run_tests; then
        log "ERROR" "DEPLOY" "Tests FAILED — aborting deploy (no changes made)"
        _notify_deploy "failure" "Deploy aborted: tests failed in ${RELEASE_DIR}"
        exit 1
    fi
else
    log "WARN" "DEPLOY" "Step 4: Tests skipped (RUN_TESTS=${RUN_TESTS:-true} SKIP_TESTS=${SKIP_TESTS})"
fi

# ════════════════════════════════════════════════════════════════════════════
# STEP 5 — SWITCH VERSION (atomic symlink)
# ════════════════════════════════════════════════════════════════════════════
step 5 "SWITCH VERSION"
module_switch_version
DEPLOY_SWITCHED=true

# ════════════════════════════════════════════════════════════════════════════
# STEP 6 — RESTART SERVICES
# ════════════════════════════════════════════════════════════════════════════
step 6 "RESTART SERVICES"
module_restart_services

# ════════════════════════════════════════════════════════════════════════════
# STEP 7 — VERIFY DEPLOYMENT
# ════════════════════════════════════════════════════════════════════════════
step 7 "VERIFY DEPLOYMENT"
if ! module_verify_deploy; then
    log "ERROR" "DEPLOY" "Health check FAILED after deploy"
    if [[ "${AUTO_ROLLBACK:-true}" == "true" ]]; then
        _do_rollback "health-check failed"
        _notify_deploy "rollback" "Auto-rolled back — health check failed after deploy ${DEPLOY_ID}"
    else
        _notify_deploy "failure" "Deploy ${DEPLOY_ID} health check failed — AUTO_ROLLBACK=false"
    fi
    exit 1
fi

# ════════════════════════════════════════════════════════════════════════════
# STEP 8 — CLEANUP OLD RELEASES
# ════════════════════════════════════════════════════════════════════════════
step 8 "CLEANUP OLD RELEASES"
if ! $DRY_RUN; then
    if [[ -d "$RELEASES_DIR" ]]; then
        local_keep="${KEEP_RELEASES:-5}"
        mapfile -t all_releases < <(
            find "$RELEASES_DIR" -maxdepth 1 -mindepth 1 -type d | sort
        )
        total_releases=${#all_releases[@]}
        if (( total_releases > local_keep )); then
            remove_count=$(( total_releases - local_keep ))
            for old_dir in "${all_releases[@]:0:${remove_count}}"; do
                rm -rf "$old_dir"
                log "OK" "CLEANUP" "Removed old release: $(basename "$old_dir")"
            done
        else
            log "INFO" "CLEANUP" "No old releases to remove (${total_releases} releases, keep=${local_keep})"
        fi
    fi
else
    log "INFO" "CLEANUP" "[DRY-RUN] Would purge old releases keeping last ${KEEP_RELEASES:-5}"
fi

# ════════════════════════════════════════════════════════════════════════════
# STEP 9 — NOTIFY SUCCESS
# ════════════════════════════════════════════════════════════════════════════
step 9 "NOTIFY"
DEPLOY_END=$(date +%s)
DEPLOY_DURATION=$(( DEPLOY_END - DEPLOY_START ))
_notify_deploy "success" "Deployed ${APP_NAME} ${DEPLOY_ID} to ${ENVIRONMENT} in ${DEPLOY_DURATION}s by ${DEPLOY_USER}"

# ════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ════════════════════════════════════════════════════════════════════════════
if [[ -t 1 ]] || $VERBOSE; then
    echo ""
    echo -e "${BOLD}${GREEN}══════ Deploy Complete ══════${RESET}"
    echo -e "  ${GREEN}App:${RESET}         ${APP_NAME}"
    echo -e "  ${GREEN}Environment:${RESET} ${ENVIRONMENT}"
    echo -e "  ${GREEN}Deploy ID:${RESET}   ${DEPLOY_ID}"
    echo -e "  ${GREEN}Release:${RESET}     ${RELEASE_DIR}"
    echo -e "  ${GREEN}Duration:${RESET}    ${DEPLOY_DURATION}s"
    echo -e "  ${GREEN}Log:${RESET}         ${LOG_FILE}"
    echo ""
fi

log "OK" "DEPLOY" "Deploy ${DEPLOY_ID} complete in ${DEPLOY_DURATION}s"
