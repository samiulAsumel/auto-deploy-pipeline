#!/usr/bin/env bash
# lib/rollback.sh — Revert to Previous Release  v1.0.0
# Sourced by deploy.sh.
# Provides: module_rollback
# Restores the previous release symlink, restarts services, and verifies.
# Can also be called directly: ./deploy.sh production --rollback
# set -euo pipefail is inherited from the orchestrator.

module_rollback() {
    local reason="${1:-manual}"
    local state_file="${ROLLBACK_STATE_FILE:-/tmp/deploy_previous}"
    local current_link="${CURRENT_LINK:-/var/www/current}"

    if $DRY_RUN; then
        log "INFO" "ROLLBACK" "[DRY-RUN] Would rollback to previous release"
        return 0
    fi

    # ── Read the previous release path ────────────────────────────────────────
    if [[ ! -f "$state_file" ]]; then
        log "ERROR" "ROLLBACK" "State file not found: ${state_file} — cannot rollback"
        return 1
    fi

    local previous
    previous=$(cat "$state_file" 2>/dev/null | tr -d '[:space:]' || true)

    if [[ -z "$previous" ]]; then
        log "ERROR" "ROLLBACK" "No previous release recorded — this was a first deploy, cannot rollback"
        return 1
    fi

    if [[ ! -d "$previous" ]]; then
        log "ERROR" "ROLLBACK" "Previous release directory missing: ${previous}"
        return 1
    fi

    local current_release
    current_release=$(readlink "$current_link" 2>/dev/null || echo "(none)")

    log "WARN" "ROLLBACK" "Reason: ${reason}"
    log "WARN" "ROLLBACK" "Rolling back: $(basename "$current_release") → $(basename "$previous")"

    # ── Switch symlink back ────────────────────────────────────────────────────
    ln -sfn "$previous" "$current_link"

    local resolved
    resolved=$(readlink "$current_link" 2>/dev/null || true)
    if [[ "$resolved" != "$previous" ]]; then
        log "ERROR" "ROLLBACK" "Symlink rollback failed: expected ${previous}, got ${resolved}"
        return 1
    fi

    log "OK" "ROLLBACK" "Symlink restored: ${current_link} → $(basename "$previous")"

    # ── Restart services with the previous release ─────────────────────────────
    log "INFO" "ROLLBACK" "Restarting services for previous release..."
    module_restart_services || log "WARN" "ROLLBACK" "Service restart failed — app may be inconsistent"

    # ── Verify rollback health ─────────────────────────────────────────────────
    log "INFO" "ROLLBACK" "Verifying rollback health..."
    local health_url="${HEALTH_URL:-}"
    if [[ -n "$health_url" ]]; then
        local attempt http_code=000
        for attempt in 1 2 3; do
            sleep 10
            http_code=$(curl -s -o /dev/null -w "%{http_code}" \
                --max-time 10 "$health_url" 2>/dev/null || echo "000")
            [[ "$http_code" == "200" ]] && break
            log "WARN" "ROLLBACK" "Rollback health check attempt ${attempt}: HTTP ${http_code}"
        done

        if [[ "$http_code" == "200" ]]; then
            log "OK" "ROLLBACK" "Rollback verified: ${health_url} → HTTP ${http_code}"
        else
            log "ERROR" "ROLLBACK" "Rollback health check FAILED (HTTP ${http_code}) — MANUAL INTERVENTION REQUIRED"
            return 1
        fi
    else
        log "INFO" "ROLLBACK" "HEALTH_URL not set — skipping rollback verification"
    fi

    # ── Clear state file to prevent double-rollback ────────────────────────────
    echo "" > "$state_file"

    log "OK" "ROLLBACK" "Rollback complete: now running $(basename "$previous")"
}
