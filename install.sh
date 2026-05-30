#!/usr/bin/env bash
# install.sh — One-command setup for Automated Deployment Pipeline v1.0.0
# Installs scripts, creates directories, sets up logrotate.
# Usage: sudo bash install.sh [--uninstall] [--dry-run]
set -euo pipefail
trap 'echo -e "\n[ERROR] Installation failed at line ${LINENO}. Check output above." >&2; exit 1' ERR

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; AMBER='\033[0;33m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[$(date '+%H:%M:%S')]  INFO ${RESET} $*"; }
ok()   { echo -e "${GREEN}[$(date '+%H:%M:%S')]   OK  ${RESET} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')]  WARN ${RESET} $*"; }
die()  { echo -e "${RED}[$(date '+%H:%M:%S')]  FAIL ${RESET} $*" >&2; exit 1; }
step() { echo -e "\n${BOLD}${AMBER}══════ $* ══════${RESET}"; }

# ── Paths ─────────────────────────────────────────────────────────────────────
INSTALL_DIR="/usr/local/bin/autodeploy"
CONFIG_DIR="/etc/autodeploy"
LOG_DIR="/var/log/deploys"
STATE_DIR="/var/lib/autodeploy"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=false
for _arg in "$@"; do
    case "$_arg" in
        --dry-run) DRY_RUN=true ;;
    esac
done

$DRY_RUN && echo -e "${YELLOW}${BOLD}[DRY-RUN] No changes will be made${RESET}\n"

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Must be run as root: sudo bash install.sh"

# ── Load config for defaults ──────────────────────────────────────────────────
if [[ -f "${SRC_DIR}/config.conf" ]]; then
    # shellcheck source=config.conf
    source "${SRC_DIR}/config.conf" 2>/dev/null || true
fi

# ── Uninstall mode ────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
    step "UNINSTALLING Automated Deployment Pipeline"
    rm -rf "$INSTALL_DIR"       && ok "Scripts removed: ${INSTALL_DIR}"
    rm -rf "$CONFIG_DIR"        && ok "Config removed: ${CONFIG_DIR}"
    rm -f /etc/logrotate.d/autodeploy && ok "Logrotate removed"
    warn "Logs preserved at ${LOG_DIR}. Remove manually: rm -rf ${LOG_DIR}"
    warn "State preserved at ${STATE_DIR}. Remove manually: rm -rf ${STATE_DIR}"
    echo -e "\n${GREEN}${BOLD}Uninstall complete.${RESET}"
    exit 0
fi

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
cat <<'BANNER'
╔══════════════════════════════════════════════════════════════════╗
║   Automated Deployment Pipeline  —  Installer  v1.0.0           ║
║   RHEL 9 / Rocky Linux / Ubuntu Server                           ║
╚══════════════════════════════════════════════════════════════════╝
BANNER
echo -e "${RESET}"

# ── Dependency check ──────────────────────────────────────────────────────────
step "Checking dependencies"

MISSING=()
for cmd in bash git curl date find; do
    command -v "$cmd" &>/dev/null && ok "Found: $cmd" || { MISSING+=("$cmd"); warn "Missing: $cmd"; }
done

[[ ${#MISSING[@]} -gt 0 ]] && die "Required commands missing: ${MISSING[*]}. Install them first."

for cmd in npm node python3 pip3 composer php pm2 mailx nc timeout; do
    command -v "$cmd" &>/dev/null \
        && ok "Found: $cmd (optional)" \
        || warn "Not found: $cmd — some features may be disabled"
done

# ── Detect OS ─────────────────────────────────────────────────────────────────
step "Detecting OS"
OS_ID="unknown"
if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID:-unknown}"
fi

case "$OS_ID" in
    rhel|centos|rocky|almalinux|fedora)
        ok "RHEL-family OS detected: ${OS_ID}"
        ;;
    ubuntu|debian)
        ok "Debian-family OS detected: ${OS_ID}"
        ;;
    *)
        warn "Unknown OS: ${OS_ID} — assuming RHEL defaults"
        ;;
esac

# ── Create directories ────────────────────────────────────────────────────────
step "Creating directories"

for dir in \
    "$INSTALL_DIR" \
    "$INSTALL_DIR/lib" \
    "$CONFIG_DIR" \
    "$LOG_DIR" \
    "$STATE_DIR" \
    "${RELEASES_DIR:-/var/www/releases}" \
    "${SHARED_DIR:-/var/www/shared}"; do
    if $DRY_RUN; then
        log "[DRY-RUN] Would create: $dir"
    else
        mkdir -p "$dir"
        ok "Created: $dir"
    fi
done

$DRY_RUN || {
    chmod 750 "$STATE_DIR" "$LOG_DIR"
    chmod 755 "${RELEASES_DIR:-/var/www/releases}" "${SHARED_DIR:-/var/www/shared}"
}

# ── Install configuration ─────────────────────────────────────────────────────
step "Installing configuration"

for conf_file in config.conf config.production.conf config.staging.conf config.dev.conf; do
    if [[ -f "${SRC_DIR}/${conf_file}" ]]; then
        if [[ -f "${CONFIG_DIR}/${conf_file}" ]]; then
            warn "Existing ${conf_file} — backing up to ${conf_file}.bak.$(date +%s)"
            $DRY_RUN || cp "${CONFIG_DIR}/${conf_file}" "${CONFIG_DIR}/${conf_file}.bak.$(date +%s)"
        fi
        if $DRY_RUN; then
            log "[DRY-RUN] Would install: ${conf_file} → ${CONFIG_DIR}/${conf_file}"
        else
            cp "${SRC_DIR}/${conf_file}" "${CONFIG_DIR}/${conf_file}"
            chmod 640 "${CONFIG_DIR}/${conf_file}"
            ln -sf "${CONFIG_DIR}/${conf_file}" "${INSTALL_DIR}/${conf_file}"
            ok "Config installed: ${CONFIG_DIR}/${conf_file}"
        fi
    fi
done

# ── Install scripts ───────────────────────────────────────────────────────────
step "Installing scripts"

if $DRY_RUN; then
    log "[DRY-RUN] Would install deploy.sh and all lib/ modules"
else
    cp "${SRC_DIR}/deploy.sh" "${INSTALL_DIR}/"
    ok "Installed: deploy.sh"

    for mod in pre_deploy backup_current pull_code run_tests switch_version \
               restart_services verify_deploy rollback notify_deploy; do
        if [[ -f "${SRC_DIR}/lib/${mod}.sh" ]]; then
            cp "${SRC_DIR}/lib/${mod}.sh" "${INSTALL_DIR}/lib/"
            ok "Installed module: lib/${mod}.sh"
        else
            warn "Module not found (skipped): lib/${mod}.sh"
        fi
    done

    if [[ -d "${SRC_DIR}/scripts" ]]; then
        cp "${SRC_DIR}/scripts/"*.sh "${INSTALL_DIR}/scripts/" 2>/dev/null || true
    fi

    find "$INSTALL_DIR" -name "*.sh" -exec chmod 755 {} \;
    ok "All scripts made executable (chmod 755)"

    # Convenience symlink
    ln -sf "${INSTALL_DIR}/deploy.sh" /usr/local/bin/deploy 2>/dev/null || true
    ok "Symlink created: /usr/local/bin/deploy → ${INSTALL_DIR}/deploy.sh"
fi

# ── Log rotation ─────────────────────────────────────────────────────────────
step "Configuring log rotation"

LOGROTATE_FILE="/etc/logrotate.d/autodeploy"
if $DRY_RUN; then
    log "[DRY-RUN] Would install logrotate config at ${LOGROTATE_FILE}"
else
    cat > "$LOGROTATE_FILE" <<LOGROTATE
${LOG_DIR}/*.log {
    weekly
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    dateext
    dateformat -%Y%m%d
}
LOGROTATE
    chmod 644 "$LOGROTATE_FILE"
    ok "Log rotation configured: ${LOGROTATE_FILE}"
fi

# ── Initial dry-run test ──────────────────────────────────────────────────────
step "Running initial validation (dry-run)"

if $DRY_RUN; then
    log "[DRY-RUN] Would run: deploy.sh production --dry-run --verbose"
else
    if bash "${INSTALL_DIR}/deploy.sh" production --dry-run --verbose 2>&1 | tail -5; then
        ok "Dry-run validation passed"
    else
        warn "Dry-run returned non-zero — check config then run manually"
        warn "  sudo bash ${INSTALL_DIR}/deploy.sh production --dry-run --verbose"
    fi
fi

# ── Post-install summary ──────────────────────────────────────────────────────
echo -e "\n${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║         Installation complete!                                   ║${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════╝${RESET}"

cat <<INFO

  Config:          ${CONFIG_DIR}/config.conf
  Scripts:         ${INSTALL_DIR}/
  Modules:         ${INSTALL_DIR}/lib/
  State:           ${STATE_DIR}/
  Logs:            ${LOG_DIR}/
  Releases:        ${RELEASES_DIR:-/var/www/releases}/
  Shared:          ${SHARED_DIR:-/var/www/shared}/

  NEXT STEPS:
  ─────────────────────────────────────────────────────────────────────
  1. Edit config:     nano ${CONFIG_DIR}/config.conf
     Set: APP_NAME, REPO_URL, APP_USER, APP_TYPE, HEALTH_URL, SLACK_WEBHOOK

  2. Production config: nano ${CONFIG_DIR}/config.production.conf

  3. Dry-run deploy:  sudo deploy production --dry-run --verbose

  4. Deploy:          sudo deploy production

  5. Rollback:        sudo deploy production --rollback

  6. Skip tests:      sudo deploy staging --skip-tests

  7. View logs:       tail -f ${LOG_DIR}/<DEPLOY_ID>.log

  8. Uninstall:       sudo bash ${SRC_DIR}/install.sh --uninstall
  ─────────────────────────────────────────────────────────────────────

  SHARED DIRECTORY (${SHARED_DIR:-/var/www/shared}):
    Place .env and upload/storage dirs here — symlinked into each release.
  ─────────────────────────────────────────────────────────────────────

INFO
