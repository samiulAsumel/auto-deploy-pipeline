#!/usr/bin/env bash
# lib/pre_deploy.sh — Pre-Deployment Checks  v1.0.0
# Sourced by deploy.sh.
# Provides: module_pre_deploy
# set -euo pipefail is inherited from the orchestrator.

# ── Verify minimum free disk space ───────────────────────────────────────────
_check_disk_space() {
    local required_mb="${MIN_DISK_MB:-2048}"
    local deploy_path="${DEPLOY_BASE:-/var/www}"
    local mount_point free_kb free_mb

    # Find the mount point that hosts DEPLOY_BASE
    mount_point=$(df "$deploy_path" 2>/dev/null | tail -1 | awk '{print $6}')
    free_kb=$(df "$deploy_path" 2>/dev/null | tail -1 | awk '{print $4}')
    free_mb=$(( free_kb / 1024 ))

    if (( free_mb < required_mb )); then
        log "ERROR" "PREFLIGHT" "Disk space too low: ${free_mb}MB free on ${mount_point} (need ${required_mb}MB)"
        return 1
    fi

    log "OK" "PREFLIGHT" "Disk space OK: ${free_mb}MB free on ${mount_point} (need ${required_mb}MB)"
}

# ── Verify Git repo is reachable ─────────────────────────────────────────────
_check_git_access() {
    local repo="${REPO_URL:-}"
    [[ -z "$repo" ]] && { log "ERROR" "PREFLIGHT" "REPO_URL not set in config.conf"; return 1; }

    if command -v git &>/dev/null; then
        if git ls-remote --quiet "$repo" HEAD &>/dev/null; then
            log "OK" "PREFLIGHT" "Git repo accessible: ${repo}"
        else
            log "ERROR" "PREFLIGHT" "Cannot reach git repo: ${repo}"
            return 1
        fi
    else
        log "ERROR" "PREFLIGHT" "git not found — cannot deploy"
        return 1
    fi
}

# ── Verify current site is responding (so we have something to roll back to) ──
_check_current_site() {
    local health_url="${HEALTH_URL:-}"
    [[ -z "$health_url" ]] && { log "WARN" "PREFLIGHT" "HEALTH_URL not set — skipping site check"; return 0; }
    [[ ! -L "${CURRENT_LINK:-/var/www/current}" ]] && {
        log "INFO" "PREFLIGHT" "No current release symlink — first deploy, skipping site check"
        return 0
    }

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$health_url" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" ]]; then
        log "OK" "PREFLIGHT" "Current site responding: ${health_url} → HTTP ${http_code}"
    else
        log "WARN" "PREFLIGHT" "Current site not responding normally (HTTP ${http_code}) — proceeding with caution"
    fi
}

# ── Verify database connection ────────────────────────────────────────────────
_check_db_connection() {
    [[ "${CHECK_DB:-true}" != "true" ]] && return 0

    local host="${DB_HOST:-localhost}"
    local port="${DB_PORT:-5432}"

    if command -v nc &>/dev/null; then
        if nc -z -w5 "$host" "$port" 2>/dev/null; then
            log "OK" "PREFLIGHT" "Database reachable: ${host}:${port}"
        else
            log "ERROR" "PREFLIGHT" "Cannot reach database: ${host}:${port}"
            return 1
        fi
    elif command -v bash &>/dev/null; then
        if timeout 5 bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null; then
            log "OK" "PREFLIGHT" "Database reachable: ${host}:${port}"
        else
            log "ERROR" "PREFLIGHT" "Cannot reach database: ${host}:${port}"
            return 1
        fi
    else
        log "WARN" "PREFLIGHT" "Neither nc nor /dev/tcp available — skipping DB check"
    fi
}

# ── Verify required tools are present ────────────────────────────────────────
_check_required_tools() {
    local missing=()
    local required_tools=(git curl)

    case "${APP_TYPE:-nodejs}" in
        nodejs) required_tools+=(node npm) ;;
        python) required_tools+=(python3 pip3) ;;
        php)    required_tools+=(php composer) ;;
        static) ;;
    esac

    for cmd in "${required_tools[@]}"; do
        command -v "$cmd" &>/dev/null \
            && log "OK" "PREFLIGHT" "Tool found: ${cmd}" \
            || missing+=("$cmd")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "ERROR" "PREFLIGHT" "Required tools missing: ${missing[*]}"
        return 1
    fi
}

# ── Verify RELEASES_DIR and SHARED_DIR exist (or create them) ────────────────
_check_directories() {
    if $DRY_RUN; then
        log "INFO" "PREFLIGHT" "[DRY-RUN] Would create: ${RELEASES_DIR} ${SHARED_DIR}"
        return 0
    fi

    for dir in "$RELEASES_DIR" "$SHARED_DIR"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log "OK" "PREFLIGHT" "Created directory: ${dir}"
        else
            log "OK" "PREFLIGHT" "Directory exists: ${dir}"
        fi
    done

    chown -R "${APP_USER:-appuser}:${APP_GROUP:-appuser}" \
        "$RELEASES_DIR" "$SHARED_DIR" 2>/dev/null || true
}

# ── Public entry point ────────────────────────────────────────────────────────
module_pre_deploy() {
    local failed=0

    $DRY_RUN && { log "INFO" "PREFLIGHT" "[DRY-RUN] Pre-flight checks (read-only)"; }

    _check_required_tools || (( failed++ ))
    _check_disk_space      || (( failed++ ))
    _check_git_access      || (( failed++ ))
    _check_current_site    || true            # warn only, don't block
    _check_db_connection   || (( failed++ ))
    _check_directories     || (( failed++ ))

    if (( failed > 0 )); then
        log "ERROR" "PREFLIGHT" "${failed} pre-flight check(s) FAILED — aborting deploy"
        return 1
    fi

    log "OK" "PREFLIGHT" "All pre-flight checks passed"
}
