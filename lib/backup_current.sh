#!/usr/bin/env bash
# lib/backup_current.sh — Backup Current Version Pointer  v1.0.0
# Sourced by deploy.sh.
# Provides: module_backup_current
# Records the current release path so rollback.sh can restore it.
# Note: No file copy needed — releases/ directory retains all versions.
# set -euo pipefail is inherited from the orchestrator.

module_backup_current() {
    local current_link="${CURRENT_LINK:-/var/www/current}"
    local state_file="${ROLLBACK_STATE_FILE:-/tmp/deploy_previous}"

    if $DRY_RUN; then
        log "INFO" "BACKUP" "[DRY-RUN] Would record current release pointer"
        return 0
    fi

    if [[ ! -L "$current_link" ]]; then
        log "INFO" "BACKUP" "No current symlink at ${current_link} — first deploy, nothing to back up"
        # Write empty file so rollback.sh handles gracefully
        echo "" > "$state_file"
        return 0
    fi

    local previous_release
    previous_release=$(readlink "$current_link" 2>/dev/null || true)

    if [[ -z "$previous_release" ]]; then
        log "WARN" "BACKUP" "Current symlink exists but readlink returned empty — skipping"
        echo "" > "$state_file"
        return 0
    fi

    if [[ ! -d "$previous_release" ]]; then
        log "WARN" "BACKUP" "Previous release directory missing: ${previous_release}"
        echo "" > "$state_file"
        return 0
    fi

    echo "$previous_release" > "$state_file"
    chmod 600 "$state_file"

    local release_id; release_id=$(basename "$previous_release")
    log "OK" "BACKUP" "Previous release recorded: ${release_id}"
    log "OK" "BACKUP" "State file: ${state_file}"
}
