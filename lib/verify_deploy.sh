#!/usr/bin/env bash
# lib/verify_deploy.sh — Post-Deploy Health Check  v1.0.0
# Sourced by deploy.sh.
# Provides: module_verify_deploy
# Polls HEALTH_URL after deploy. Returns 0 on success, 1 on failure (triggers rollback).
# set -euo pipefail is inherited from the orchestrator.

module_verify_deploy() {
    local health_url="${HEALTH_URL:-}"
    local retries="${HEALTH_RETRIES:-3}"
    local interval="${HEALTH_RETRY_INTERVAL:-10}"
    local warmup="${HEALTH_WARMUP:-10}"

    if [[ -z "$health_url" ]]; then
        log "WARN" "VERIFY" "HEALTH_URL not set — skipping post-deploy health check"
        return 0
    fi

    if $DRY_RUN; then
        log "INFO" "VERIFY" "[DRY-RUN] Would health-check: ${health_url} (${retries} retries, ${interval}s interval)"
        return 0
    fi

    log "INFO" "VERIFY" "Waiting ${warmup}s for app to start..."
    sleep "$warmup"

    local attempt http_code
    for (( attempt = 1; attempt <= retries; attempt++ )); do
        log "INFO" "VERIFY" "Health check attempt ${attempt}/${retries}: ${health_url}"

        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 15 --connect-timeout 10 \
            "$health_url" 2>/dev/null || echo "000")

        if [[ "$http_code" == "200" ]]; then
            log "OK" "VERIFY" "Health check PASSED (HTTP ${http_code}) on attempt ${attempt}"
            return 0
        fi

        log "WARN" "VERIFY" "Health check attempt ${attempt} returned HTTP ${http_code}"

        if (( attempt < retries )); then
            log "INFO" "VERIFY" "Waiting ${interval}s before retry..."
            sleep "$interval"
        fi
    done

    log "ERROR" "VERIFY" "Health check FAILED after ${retries} attempts (last HTTP ${http_code})"
    return 1
}
