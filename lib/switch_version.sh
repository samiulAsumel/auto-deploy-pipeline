#!/usr/bin/env bash
# lib/switch_version.sh — Atomic Symlink Switch  v1.0.0
# Sourced by deploy.sh.
# Provides: module_switch_version
# Atomically points CURRENT_LINK at the new release directory.
# Uses ln -sfn which is atomic on most Linux filesystems.
# set -euo pipefail is inherited from the orchestrator.

module_switch_version() {
    local current_link="${CURRENT_LINK:-/var/www/current}"
    local release_dir="${RELEASE_DIR}"

    if [[ ! -d "$release_dir" ]] && ! $DRY_RUN; then
        log "ERROR" "SWITCH" "Release directory not found: ${release_dir}"
        return 1
    fi

    if $DRY_RUN; then
        log "INFO" "SWITCH" "[DRY-RUN] Would: ln -sfn ${release_dir} ${current_link}"
        return 0
    fi

    # Ensure parent directory of the symlink exists
    mkdir -p "$(dirname "$current_link")"

    # Atomic switch — ln -sfn replaces the symlink in one syscall
    ln -sfn "$release_dir" "$current_link"

    # Verify the switch succeeded
    local resolved
    resolved=$(readlink "$current_link" 2>/dev/null || true)

    if [[ "$resolved" != "$release_dir" ]]; then
        log "ERROR" "SWITCH" "Symlink switch failed: ${current_link} → ${resolved} (expected ${release_dir})"
        return 1
    fi

    log "OK" "SWITCH" "Symlink updated: ${current_link} → $(basename "$release_dir")"
}
