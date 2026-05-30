#!/usr/bin/env bash
# lib/notify_deploy.sh — Deployment Notifications  v1.0.0
# Sourced by deploy.sh.
# Provides: _notify_deploy
# Sends Slack webhook and/or email notifications on deploy success/failure/rollback.
# set -euo pipefail is inherited from the orchestrator.

# ── Slack notification ────────────────────────────────────────────────────────
_notify_slack() {
    local status="$1" message="$2"
    local webhook="${SLACK_WEBHOOK:-}"

    [[ -z "$webhook" ]] && return 0
    command -v curl &>/dev/null || { log "WARN" "NOTIFY" "curl not found — Slack notification skipped"; return 0; }

    local emoji colour
    case "${status}" in
        success)  emoji="✅"; colour="good"    ;;
        failure)  emoji="❌"; colour="danger"  ;;
        rollback) emoji="⚠️"; colour="warning" ;;
        *)        emoji="ℹ️"; colour="#439FE0" ;;
    esac

    local git_ref=""
    [[ -d "${RELEASE_DIR:-}" ]] && \
        git_ref=$(git -C "${RELEASE_DIR}" rev-parse --short HEAD 2>/dev/null || true)

    local payload
    payload=$(cat <<JSON
{
  "attachments": [{
    "color": "${colour}",
    "fallback": "${emoji} ${message}",
    "title": "${emoji} Deploy ${status^^}: ${APP_NAME:-app}",
    "text": "${message}",
    "fields": [
      { "title": "Environment", "value": "${ENVIRONMENT:-unknown}", "short": true },
      { "title": "Deploy ID",   "value": "${DEPLOY_ID:-unknown}",   "short": true },
      { "title": "Branch",      "value": "${BRANCH:-main}",         "short": true },
      { "title": "Commit",      "value": "${git_ref:-n/a}",         "short": true },
      { "title": "User",        "value": "${DEPLOY_USER:-unknown}",  "short": true },
      { "title": "Server",      "value": "$(hostname -s 2>/dev/null || echo unknown)", "short": true }
    ],
    "footer": "auto-deploy-pipeline v${VERSION:-1.0.0}",
    "ts": $(date +%s)
  }]
}
JSON
)

    local resp
    resp=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST -H 'Content-type: application/json' \
        --data "$payload" \
        --max-time 10 \
        "$webhook" 2>/dev/null || echo "000")

    if [[ "$resp" == "200" ]]; then
        log "OK" "NOTIFY" "Slack notification sent (${status})"
    else
        log "WARN" "NOTIFY" "Slack notification failed (HTTP ${resp})"
    fi
}

# ── Email notification ────────────────────────────────────────────────────────
_notify_email() {
    local status="$1" message="$2"
    local to="${NOTIFY_EMAIL:-}"

    [[ -z "$to" ]] && return 0

    local mail_cmd=""
    command -v mailx    &>/dev/null && mail_cmd="mailx"
    command -v sendmail &>/dev/null && mail_cmd="${mail_cmd:-sendmail}"
    command -v mail     &>/dev/null && mail_cmd="${mail_cmd:-mail}"

    if [[ -z "$mail_cmd" ]]; then
        log "WARN" "NOTIFY" "No mail command found (mailx/mail/sendmail) — email skipped"
        return 0
    fi

    local subject="[autodeploy] ${APP_NAME:-app} deploy ${status^^} — ${ENVIRONMENT:-env} ${DEPLOY_ID:-}"
    local body
    body=$(cat <<BODY
Deployment Notification
=======================
Status:      ${status^^}
App:         ${APP_NAME:-app}
Environment: ${ENVIRONMENT:-unknown}
Deploy ID:   ${DEPLOY_ID:-unknown}
Branch:      ${BRANCH:-main}
Server:      $(hostname -f 2>/dev/null || echo unknown)
User:        ${DEPLOY_USER:-unknown}
Time:        $(date '+%Y-%m-%d %H:%M:%S')

Message: ${message}

Log file: ${LOG_FILE:-/var/log/deploys/${DEPLOY_ID:-}.log}

--
auto-deploy-pipeline v${VERSION:-1.0.0}
BODY
)

    case "$mail_cmd" in
        mailx|mail)
            echo "$body" | mailx -s "$subject" "$to" 2>/dev/null \
                && log "OK" "NOTIFY" "Email sent to ${to}" \
                || log "WARN" "NOTIFY" "Email delivery failed"
            ;;
        sendmail)
            (echo "To: ${to}"; echo "Subject: ${subject}"; echo ""; echo "$body") \
                | sendmail -t 2>/dev/null \
                && log "OK" "NOTIFY" "Email sent via sendmail to ${to}" \
                || log "WARN" "NOTIFY" "sendmail delivery failed"
            ;;
    esac
}

# ── Public entry point ────────────────────────────────────────────────────────
# Usage: _notify_deploy <status> <message>
#   status: success | failure | rollback
_notify_deploy() {
    local status="$1" message="$2"
    local notify_on="${NOTIFY_ON:-both}"
    local notify_method="${NOTIFY_METHOD:-slack}"

    # Decide whether to notify based on status + NOTIFY_ON setting
    case "$notify_on" in
        success)
            [[ "$status" != "success" ]] && return 0
            ;;
        failure)
            [[ "$status" == "success" ]] && return 0
            ;;
        both|*) ;;
    esac

    $DRY_RUN && {
        log "INFO" "NOTIFY" "[DRY-RUN] Would notify (${notify_method}): ${status} — ${message}"
        return 0
    }

    case "$notify_method" in
        slack)       _notify_slack "$status" "$message" ;;
        email)       _notify_email "$status" "$message" ;;
        both|all)    _notify_slack "$status" "$message"; _notify_email "$status" "$message" ;;
        none)        log "INFO" "NOTIFY" "NOTIFY_METHOD=none — notifications disabled" ;;
        *)           log "WARN" "NOTIFY" "Unknown NOTIFY_METHOD: ${notify_method}" ;;
    esac
}
