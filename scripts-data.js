// scripts-data.js — Embedded script content for the web script explorer

const SCRIPTS_DATA = [
  {
    id: 'config',
    name: 'config.conf',
    path: 'config.conf',
    description: 'Central configuration for all deploy settings. Set APP_NAME, REPO_URL, APP_TYPE, HEALTH_URL, and SLACK_WEBHOOK. Edit this file first — environment-specific overrides go in config.production.conf etc.',
    badges: ['config'],
    code: `# Automated Deployment Pipeline — config.conf v1.0.0

APP_NAME="myapp"
APP_USER="appuser"
APP_GROUP="appuser"

REPO_URL="git@github.com:company/app.git"
BRANCH="main"

DEPLOY_BASE="/var/www"
RELEASES_DIR="/var/www/releases"
CURRENT_LINK="/var/www/current"
SHARED_DIR="/var/www/shared"

KEEP_RELEASES=5

# nodejs | python | php | static
APP_TYPE="nodejs"

BUILD_ENABLED=true
BUILD_CMD="npm run build"

RUN_TESTS=true
TEST_CMD="npm test"
TEST_TIMEOUT=300

SHARED_FILES=".env storage uploads"

WEBSERVER="nginx"
APP_SERVER="pm2"
PM2_APP_NAME="myapp"

HEALTH_URL="http://localhost:3000/health"
HEALTH_RETRIES=3
HEALTH_RETRY_INTERVAL=10
HEALTH_WARMUP=10

DB_MIGRATE=false
DB_HOST="localhost"
DB_PORT=5432
MIN_DISK_MB=2048
CHECK_DB=true

AUTO_ROLLBACK=true

NOTIFY_METHOD="slack"   # email | slack | both | none
NOTIFY_ON="both"        # success | failure | both
NOTIFY_EMAIL="devops@company.com"
SLACK_WEBHOOK=""        # https://hooks.slack.com/services/...

LOG_DIR="/var/log/deploys"
STATE_DIR="/var/lib/autodeploy"
VERSION="1.0.0"`
  },
  {
    id: 'deploy',
    name: 'deploy.sh',
    path: 'deploy.sh',
    description: 'Main orchestrator. Accepts environment as argument, loads config, runs all 9 steps in order. On any failure after the symlink switch, auto-rollback fires. Pass --rollback to revert manually.',
    badges: ['main'],
    code: `#!/usr/bin/env bash
# deploy.sh — Main Orchestrator v1.0.0
# Usage: ./deploy.sh production [--dry-run] [--verbose] [--skip-tests] [--rollback]

set -euo pipefail
trap '_on_error \$LINENO "\$BASH_COMMAND"' ERR

ENVIRONMENT="\${1:-}"
DRY_RUN=false; VERBOSE=false; SKIP_TESTS=false; DO_ROLLBACK=false

[[ -z "\$ENVIRONMENT" ]] && { echo "Usage: \$0 <environment>"; exit 1; }

# Load base + environment-specific config
source "\$SCRIPT_DIR/config.conf"
[[ -f "\$SCRIPT_DIR/config.\${ENVIRONMENT}.conf" ]] && source "\$SCRIPT_DIR/config.\${ENVIRONMENT}.conf"

# Source all lib/ modules
for _mod in pre_deploy backup_current pull_code run_tests \\
            switch_version restart_services verify_deploy rollback notify_deploy; do
    source "\${SCRIPT_DIR}/lib/\${_mod}.sh"
done

DEPLOY_ID=\$(date +%Y%m%d-%H%M%S)
RELEASE_DIR="\${RELEASES_DIR}/\${DEPLOY_ID}"

# ── Deployment flow ───────────────────────────────────────
acquire_lock

step 1 "PRE-FLIGHT CHECKS"  && module_pre_deploy
step 2 "BACKUP CURRENT"     && module_backup_current
step 3 "PULL CODE"          && module_pull_code

if [[ "\${RUN_TESTS}" == "true" ]] && ! \$SKIP_TESTS; then
    step 4 "RUN TESTS"
    module_run_tests || { _notify_deploy "failure" "Tests failed"; exit 1; }
fi

step 5 "SWITCH VERSION"     && module_switch_version && DEPLOY_SWITCHED=true
step 6 "RESTART SERVICES"   && module_restart_services

step 7 "VERIFY DEPLOYMENT"
module_verify_deploy || { _do_rollback "health-check failed"; exit 1; }

step 8 "CLEANUP OLD RELEASES"
# keep last KEEP_RELEASES; delete the rest

step 9 "NOTIFY"
_notify_deploy "success" "Deployed \${APP_NAME} \${DEPLOY_ID} to \${ENVIRONMENT}"

log "OK" "DEPLOY" "Complete in \${DEPLOY_DURATION}s"`
  },
  {
    id: 'pre_deploy',
    name: 'lib/pre_deploy.sh',
    path: 'lib/pre_deploy.sh',
    description: 'Pre-flight checks before any code is touched. Verifies disk space, git access, database connectivity, required tools, and creates release directories.',
    badges: ['lib'],
    code: `#!/usr/bin/env bash
# lib/pre_deploy.sh — Pre-Deployment Checks v1.0.0

module_pre_deploy() {
    local failed=0

    _check_required_tools || (( failed++ ))  # git, curl, npm/pip/php
    _check_disk_space      || (( failed++ ))  # MIN_DISK_MB free
    _check_git_access      || (( failed++ ))  # git ls-remote REPO_URL
    _check_current_site    || true            # warn only
    _check_db_connection   || (( failed++ ))  # nc host port
    _check_directories     || (( failed++ ))  # mkdir releases/ shared/

    if (( failed > 0 )); then
        log "ERROR" "PREFLIGHT" "\${failed} check(s) FAILED — aborting"
        return 1
    fi

    log "OK" "PREFLIGHT" "All pre-flight checks passed"
}`
  },
  {
    id: 'backup_current',
    name: 'lib/backup_current.sh',
    path: 'lib/backup_current.sh',
    description: 'Records the current release path so rollback.sh can restore it. No file copy needed — the releases/ directory retains all versions. Writes the path to ROLLBACK_STATE_FILE.',
    badges: ['lib'],
    code: `#!/usr/bin/env bash
# lib/backup_current.sh — Backup Current Version Pointer v1.0.0

module_backup_current() {
    local current_link="\${CURRENT_LINK:-/var/www/current}"
    local state_file="\${ROLLBACK_STATE_FILE:-/tmp/deploy_previous}"

    if [[ ! -L "\$current_link" ]]; then
        log "INFO" "BACKUP" "First deploy — nothing to record"
        echo "" > "\$state_file"
        return 0
    fi

    local previous; previous=\$(readlink "\$current_link")
    echo "\$previous" > "\$state_file"
    chmod 600 "\$state_file"

    log "OK" "BACKUP" "Previous release recorded: \$(basename "\$previous")"
}`
  },
  {
    id: 'pull_code',
    name: 'lib/pull_code.sh',
    path: 'lib/pull_code.sh',
    description: 'Clones the repo at the configured branch into RELEASES_DIR/DEPLOY_ID, links shared files (.env, uploads) from SHARED_DIR, installs dependencies, and runs the build command.',
    badges: ['lib'],
    code: `#!/usr/bin/env bash
# lib/pull_code.sh — Clone & Install Dependencies v1.0.0

module_pull_code() {
    # 1. Clone repo into new release directory
    git clone --depth 1 --branch "\$BRANCH" "\$REPO_URL" "\$RELEASE_DIR"

    # 2. Link shared files (.env, uploads, storage)
    for item in \$SHARED_FILES; do
        ln -sfn "\${SHARED_DIR}/\${item}" "\${RELEASE_DIR}/\${item}"
    done

    # 3. Install dependencies based on APP_TYPE
    case "\$APP_TYPE" in
        nodejs)  npm ci --production        ;;
        python)  pip install -r requirements.txt ;;
        php)     composer install --no-dev  ;;
        static)  : # nothing extra          ;;
    esac

    # 4. Build (if BUILD_ENABLED=true)
    [[ "\${BUILD_ENABLED}" == "true" ]] && eval "\$BUILD_CMD"

    log "OK" "PULL" "Release ready: \$(basename "\$RELEASE_DIR")"
}`
  },
  {
    id: 'run_tests',
    name: 'lib/run_tests.sh',
    path: 'lib/run_tests.sh',
    description: 'Runs the configured test suite inside the new release directory. Aborts the deploy (before any switch) if tests fail or time out. Safe — no production code is touched.',
    badges: ['lib'],
    code: `#!/usr/bin/env bash
# lib/run_tests.sh — Test Suite Runner v1.0.0

module_run_tests() {
    local test_cmd="\${TEST_CMD:-npm test}"
    local test_timeout="\${TEST_TIMEOUT:-300}"

    log "INFO" "TESTS" "Running: \${test_cmd} (timeout: \${test_timeout}s)"
    cd "\$RELEASE_DIR"

    # Run under timeout; stream output to deploy log
    timeout "\$test_timeout" bash -c "\$test_cmd" 2>&1 \\
        | while IFS= read -r line; do log "INFO" "TESTS" "\$line"; done

    local exit_code=\${PIPESTATUS[0]}

    [[ "\$exit_code" -eq 124 ]] && { log "ERROR" "TESTS" "Timed out after \${test_timeout}s"; return 1; }
    [[ "\$exit_code" -ne 0  ]] && { log "ERROR" "TESTS" "FAILED (exit \${exit_code})"; return 1; }

    log "OK" "TESTS" "PASSED"
}`
  },
  {
    id: 'switch_version',
    name: 'lib/switch_version.sh',
    path: 'lib/switch_version.sh',
    description: 'Atomically switches the CURRENT_LINK symlink to the new release directory. The ln -sfn call is a single syscall — zero downtime. Verifies the switch succeeded before returning.',
    badges: ['lib'],
    code: `#!/usr/bin/env bash
# lib/switch_version.sh — Atomic Symlink Switch v1.0.0

module_switch_version() {
    local current_link="\${CURRENT_LINK:-/var/www/current}"

    # ln -sfn is atomic — a single rename(2) syscall on Linux
    ln -sfn "\$RELEASE_DIR" "\$current_link"

    local resolved; resolved=\$(readlink "\$current_link")
    [[ "\$resolved" != "\$RELEASE_DIR" ]] && {
        log "ERROR" "SWITCH" "Symlink switch failed"
        return 1
    }

    log "OK" "SWITCH" "\${current_link} → \$(basename "\$RELEASE_DIR")"
}`
  },
  {
    id: 'restart_services',
    name: 'lib/restart_services.sh',
    path: 'lib/restart_services.sh',
    description: 'Restarts the app process manager (pm2 reload / gunicorn / php-fpm) and reloads the web server (nginx config test then reload, or apache graceful). Falls back gracefully if a method is unavailable.',
    badges: ['lib'],
    code: `#!/usr/bin/env bash
# lib/restart_services.sh — Restart App & Web Server v1.0.0

module_restart_services() {
    _restart_app_server
    _reload_web_server
}

_restart_app_server() {
    case "\${APP_SERVER:-pm2}" in
        pm2)
            pm2 reload "\${PM2_APP_NAME}" || pm2 restart "\${PM2_APP_NAME}"
            pm2 save --force
            ;;
        gunicorn) systemctl restart "\${GUNICORN_SERVICE}" ;;
        php-fpm)  systemctl reload  "\${PHP_FPM_SERVICE}"  ;;
        none) : ;;
    esac
}

_reload_web_server() {
    case "\${WEBSERVER:-nginx}" in
        nginx)
            nginx -t && systemctl reload "\${NGINX_SERVICE:-nginx}"
            ;;
        apache)
            apachectl -t && systemctl reload "\${APACHE_SERVICE:-httpd}" \\
                || apachectl graceful
            ;;
        none) : ;;
    esac
}`
  },
  {
    id: 'verify_deploy',
    name: 'lib/verify_deploy.sh',
    path: 'lib/verify_deploy.sh',
    description: 'Polls HEALTH_URL after deploy. Waits HEALTH_WARMUP seconds for the app to start, then retries up to HEALTH_RETRIES times. Returns 1 on failure — which triggers auto-rollback in deploy.sh.',
    badges: ['lib'],
    code: `#!/usr/bin/env bash
# lib/verify_deploy.sh — Post-Deploy Health Check v1.0.0

module_verify_deploy() {
    local url="\${HEALTH_URL:-}"
    [[ -z "\$url" ]] && { log "WARN" "VERIFY" "HEALTH_URL not set — skipping"; return 0; }

    log "INFO" "VERIFY" "Waiting \${HEALTH_WARMUP:-10}s for app start..."
    sleep "\${HEALTH_WARMUP:-10}"

    local attempt http_code
    for (( attempt=1; attempt<=\${HEALTH_RETRIES:-3}; attempt++ )); do
        http_code=\$(curl -s -o /dev/null -w "%{http_code}" \\
            --max-time 15 "\$url" 2>/dev/null || echo 000)

        [[ "\$http_code" == "200" ]] && {
            log "OK" "VERIFY" "PASSED (HTTP \${http_code}) on attempt \${attempt}"
            return 0
        }

        log "WARN" "VERIFY" "Attempt \${attempt}: HTTP \${http_code}"
        sleep "\${HEALTH_RETRY_INTERVAL:-10}"
    done

    log "ERROR" "VERIFY" "FAILED after \${HEALTH_RETRIES:-3} attempts"
    return 1
}`
  },
  {
    id: 'rollback',
    name: 'lib/rollback.sh',
    path: 'lib/rollback.sh',
    description: 'Reads the previous release path from ROLLBACK_STATE_FILE, restores the symlink, restarts services, and verifies health. Called automatically on failure or manually with --rollback.',
    badges: ['lib'],
    code: `#!/usr/bin/env bash
# lib/rollback.sh — Revert to Previous Release v1.0.0

module_rollback() {
    local reason="\${1:-manual}"
    local state_file="\${ROLLBACK_STATE_FILE:-/tmp/deploy_previous}"

    local previous; previous=\$(cat "\$state_file" 2>/dev/null | tr -d '[:space:]')

    [[ -z "\$previous"  ]] && { log "ERROR" "ROLLBACK" "No previous release recorded"; return 1; }
    [[ ! -d "\$previous" ]] && { log "ERROR" "ROLLBACK" "Previous dir missing: \$previous"; return 1; }

    log "WARN" "ROLLBACK" "Reason: \$reason"
    log "WARN" "ROLLBACK" "Restoring: \$(basename "\$previous")"

    # Atomic switch back
    ln -sfn "\$previous" "\${CURRENT_LINK}"

    # Restart + verify
    module_restart_services
    sleep 10

    local http_code
    http_code=\$(curl -s -o /dev/null -w "%{http_code}" "\${HEALTH_URL}" || echo 000)
    [[ "\$http_code" == "200" ]] \\
        && log "OK" "ROLLBACK" "Rollback verified — running \$(basename "\$previous")" \\
        || log "ERROR" "ROLLBACK" "Rollback health check FAILED — MANUAL INTERVENTION NEEDED"

    echo "" > "\$state_file"
}`
  },
  {
    id: 'notify_deploy',
    name: 'lib/notify_deploy.sh',
    path: 'lib/notify_deploy.sh',
    description: 'Sends Slack webhook (colour-coded) and/or email notifications on success, failure, or rollback. Respects NOTIFY_ON and NOTIFY_METHOD config settings.',
    badges: ['lib'],
    code: `#!/usr/bin/env bash
# lib/notify_deploy.sh — Deployment Notifications v1.0.0

_notify_deploy() {
    local status="\$1" message="\$2"

    case "\${NOTIFY_METHOD:-slack}" in
        slack) _notify_slack "\$status" "\$message" ;;
        email) _notify_email "\$status" "\$message" ;;
        both)
            _notify_slack "\$status" "\$message"
            _notify_email "\$status" "\$message"
            ;;
    esac
}

_notify_slack() {
    local status="\$1" message="\$2"
    local colour; case "\$status" in
        success)  colour="good"    ;;
        failure)  colour="danger"  ;;
        rollback) colour="warning" ;;
    esac

    curl -s -X POST -H 'Content-type: application/json' \\
        --data "{
          \\"attachments\\": [{
            \\"color\\": \\"\$colour\\",
            \\"title\\": \\"Deploy \${status^^}: \${APP_NAME}\\",
            \\"text\\": \\"\$message\\",
            \\"fields\\": [
              {\\"title\\": \\"Environment\\", \\"value\\": \\"\${ENVIRONMENT}\\", \\"short\\": true},
              {\\"title\\": \\"Deploy ID\\",   \\"value\\": \\"\${DEPLOY_ID}\\",   \\"short\\": true}
            ]
          }]
        }" "\${SLACK_WEBHOOK}"
}`
  },
  {
    id: 'install',
    name: 'install.sh',
    path: 'install.sh',
    description: 'One-command setup. Creates directories, installs scripts to /usr/local/bin/autodeploy, adds a /usr/local/bin/deploy symlink, configures logrotate, and runs a dry-run validation.',
    badges: ['install'],
    code: `#!/usr/bin/env bash
# install.sh — One-command setup v1.0.0
# Usage: sudo bash install.sh [--uninstall] [--dry-run]

INSTALL_DIR="/usr/local/bin/autodeploy"
CONFIG_DIR="/etc/autodeploy"
LOG_DIR="/var/log/deploys"
STATE_DIR="/var/lib/autodeploy"

# Creates dirs, installs scripts, sets up logrotate
# Adds convenience symlink: /usr/local/bin/deploy

sudo bash install.sh           # install
sudo bash install.sh --dry-run # preview only
sudo bash install.sh --uninstall`
  }
];
