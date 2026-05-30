#!/usr/bin/env bash
# lib/pull_code.sh — Clone Repository & Install Dependencies  v1.0.0
# Sourced by deploy.sh.
# Provides: module_pull_code
# Clones repo into RELEASE_DIR, links shared files, installs deps, runs build.
# set -euo pipefail is inherited from the orchestrator.

# ── Clone the repository ──────────────────────────────────────────────────────
_git_clone() {
    local repo="${REPO_URL}"
    local branch="${BRANCH:-main}"
    local target="${RELEASE_DIR}"

    log "INFO" "PULL" "Cloning ${repo} (branch: ${branch}) → ${target}"

    if $DRY_RUN; then
        log "INFO" "PULL" "[DRY-RUN] Would: git clone --depth 1 --branch ${branch} ${repo} ${target}"
        return 0
    fi

    mkdir -p "$target"

    git clone --depth 1 --branch "$branch" "$repo" "$target" 2>&1 \
        | while IFS= read -r line; do log "INFO" "PULL" "$line"; done

    local git_ref
    git_ref=$(git -C "$target" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    log "OK" "PULL" "Cloned commit: ${git_ref} (branch: ${branch})"
}

# ── Link shared files / dirs from SHARED_DIR into the new release ─────────────
_link_shared_files() {
    local shared="${SHARED_DIR:-/var/www/shared}"
    local shared_list="${SHARED_FILES:-.env}"

    $DRY_RUN && { log "INFO" "PULL" "[DRY-RUN] Would link shared files: ${shared_list}"; return 0; }

    mkdir -p "$shared"

    for item in $shared_list; do
        local shared_path="${shared}/${item##*/}"
        local release_path="${RELEASE_DIR}/${item}"

        # Create placeholder in shared if it doesn't exist yet
        if [[ ! -e "$shared_path" ]]; then
            if [[ "$item" == */ ]] || [[ -d "${RELEASE_DIR}/${item}" ]]; then
                mkdir -p "$shared_path"
            else
                touch "$shared_path"
            fi
            log "INFO" "PULL" "Created shared placeholder: ${shared_path}"
        fi

        # Remove from release dir if it was cloned
        [[ -e "$release_path" ]] && rm -rf "$release_path"

        # Make parent dir if needed
        mkdir -p "$(dirname "$release_path")"
        ln -sfn "$shared_path" "$release_path"
        log "OK" "PULL" "Linked: ${release_path} → ${shared_path}"
    done
}

# ── Install dependencies based on APP_TYPE ────────────────────────────────────
_install_dependencies() {
    local app_type="${APP_TYPE:-nodejs}"

    if $DRY_RUN; then
        log "INFO" "PULL" "[DRY-RUN] Would install dependencies (${app_type})"
        return 0
    fi

    log "INFO" "PULL" "Installing dependencies (${app_type})..."
    cd "$RELEASE_DIR"

    case "$app_type" in
        nodejs)
            [[ -f package.json ]] || { log "WARN" "PULL" "No package.json found — skipping npm install"; return 0; }
            log "INFO" "PULL" "Running: npm ci --production"
            npm ci --production 2>&1 | while IFS= read -r line; do log "INFO" "PULL" "$line"; done
            log "OK" "PULL" "npm packages installed"
            ;;

        python)
            [[ -f requirements.txt ]] || { log "WARN" "PULL" "No requirements.txt — skipping pip install"; return 0; }
            local pip_cmd="pip3"
            command -v pip3 &>/dev/null || pip_cmd="pip"
            local venv_dir="${RELEASE_DIR}/.venv"
            python3 -m venv "$venv_dir" 2>/dev/null || true
            "${venv_dir}/bin/pip" install --quiet -r requirements.txt 2>&1 \
                | while IFS= read -r line; do log "INFO" "PULL" "$line"; done
            log "OK" "PULL" "Python packages installed in venv"
            ;;

        php)
            [[ -f composer.json ]] || { log "WARN" "PULL" "No composer.json — skipping composer install"; return 0; }
            if command -v composer &>/dev/null; then
                composer install --no-dev --no-interaction --quiet 2>&1 \
                    | while IFS= read -r line; do log "INFO" "PULL" "$line"; done
                log "OK" "PULL" "Composer packages installed"
            else
                log "WARN" "PULL" "composer not found — skipping"
            fi
            ;;

        static)
            log "INFO" "PULL" "Static site — no dependencies to install"
            ;;

        *)
            log "WARN" "PULL" "Unknown APP_TYPE: ${app_type} — skipping dependency install"
            ;;
    esac
}

# ── Run build step (if enabled) ───────────────────────────────────────────────
_run_build() {
    [[ "${BUILD_ENABLED:-true}" != "true" ]] && return 0

    local build_cmd="${BUILD_CMD:-npm run build}"

    if $DRY_RUN; then
        log "INFO" "PULL" "[DRY-RUN] Would run build: ${build_cmd}"
        return 0
    fi

    log "INFO" "PULL" "Running build: ${build_cmd}"
    cd "$RELEASE_DIR"

    eval "$build_cmd" 2>&1 | while IFS= read -r line; do log "INFO" "PULL" "$line"; done

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log "ERROR" "PULL" "Build command failed: ${build_cmd}"
        return 1
    fi

    log "OK" "PULL" "Build complete"
}

# ── Set ownership on the new release ─────────────────────────────────────────
_set_permissions() {
    $DRY_RUN && return 0
    chown -R "${APP_USER:-appuser}:${APP_GROUP:-appuser}" "$RELEASE_DIR" 2>/dev/null || true
    find "$RELEASE_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
    find "$RELEASE_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true
    log "OK" "PULL" "Permissions set on release directory"
}

# ── Public entry point ────────────────────────────────────────────────────────
module_pull_code() {
    _git_clone
    _link_shared_files
    _install_dependencies
    _run_build
    _set_permissions
    log "OK" "PULL" "Release prepared: ${RELEASE_DIR}"
}
