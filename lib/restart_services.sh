#!/usr/bin/env bash
# lib/restart_services.sh — Restart App Server & Web Server  v1.0.0
# Sourced by deploy.sh.
# Provides: module_restart_services
# Restarts/reloads the app process manager and web server based on config.
# set -euo pipefail is inherited from the orchestrator.

# ── App server restart ────────────────────────────────────────────────────────
_restart_app_server() {
    local app_server="${APP_SERVER:-pm2}"

    if $DRY_RUN; then
        log "INFO" "RESTART" "[DRY-RUN] Would restart app server: ${app_server}"
        return 0
    fi

    case "$app_server" in
        pm2)
            local pm2_name="${PM2_APP_NAME:-${APP_NAME:-myapp}}"
            if command -v pm2 &>/dev/null; then
                # Reload for zero-downtime; fall back to restart if reload fails
                pm2 reload "$pm2_name" 2>/dev/null \
                    && log "OK" "RESTART" "pm2 reloaded: ${pm2_name}" \
                    || {
                        log "WARN" "RESTART" "pm2 reload failed — trying pm2 restart"
                        pm2 restart "$pm2_name" 2>/dev/null \
                            && log "OK" "RESTART" "pm2 restarted: ${pm2_name}" \
                            || { log "ERROR" "RESTART" "pm2 restart FAILED: ${pm2_name}"; return 1; }
                    }
                pm2 save --force 2>/dev/null || true
            else
                log "WARN" "RESTART" "pm2 not found — app server not restarted"
            fi
            ;;

        gunicorn)
            local svc="${GUNICORN_SERVICE:-gunicorn}"
            if systemctl is-active --quiet "$svc" 2>/dev/null; then
                systemctl restart "$svc" \
                    && log "OK" "RESTART" "gunicorn restarted: ${svc}" \
                    || { log "ERROR" "RESTART" "gunicorn restart FAILED: ${svc}"; return 1; }
            else
                log "WARN" "RESTART" "Gunicorn service not active: ${svc}"
            fi
            ;;

        php-fpm)
            local svc="${PHP_FPM_SERVICE:-php-fpm}"
            if systemctl is-active --quiet "$svc" 2>/dev/null; then
                systemctl reload "$svc" 2>/dev/null \
                    && log "OK" "RESTART" "php-fpm reloaded: ${svc}" \
                    || {
                        systemctl restart "$svc" \
                            && log "OK" "RESTART" "php-fpm restarted: ${svc}" \
                            || { log "ERROR" "RESTART" "php-fpm restart FAILED: ${svc}"; return 1; }
                    }
            else
                log "WARN" "RESTART" "php-fpm service not active: ${svc}"
            fi
            ;;

        none)
            log "INFO" "RESTART" "APP_SERVER=none — skipping app server restart"
            ;;

        *)
            log "WARN" "RESTART" "Unknown APP_SERVER: ${app_server} — skipping"
            ;;
    esac
}

# ── Web server reload ─────────────────────────────────────────────────────────
_reload_web_server() {
    local webserver="${WEBSERVER:-nginx}"

    if $DRY_RUN; then
        log "INFO" "RESTART" "[DRY-RUN] Would reload web server: ${webserver}"
        return 0
    fi

    case "$webserver" in
        nginx)
            local svc="${NGINX_SERVICE:-nginx}"
            # Test config before reload
            if command -v nginx &>/dev/null; then
                nginx -t 2>/dev/null \
                    || { log "ERROR" "RESTART" "nginx config test FAILED — aborting reload"; return 1; }
            fi
            systemctl reload "$svc" 2>/dev/null \
                && log "OK" "RESTART" "nginx reloaded: ${svc}" \
                || {
                    log "WARN" "RESTART" "systemctl reload failed — trying nginx -s reload"
                    nginx -s reload 2>/dev/null \
                        && log "OK" "RESTART" "nginx reloaded via signal" \
                        || { log "ERROR" "RESTART" "nginx reload FAILED"; return 1; }
                }
            ;;

        apache)
            local svc="${APACHE_SERVICE:-httpd}"
            if command -v apachectl &>/dev/null; then
                apachectl -t 2>/dev/null \
                    || { log "ERROR" "RESTART" "apache config test FAILED — aborting reload"; return 1; }
            fi
            systemctl reload "$svc" 2>/dev/null \
                || systemctl reload apache2 2>/dev/null \
                || apachectl graceful 2>/dev/null \
                && log "OK" "RESTART" "Apache reloaded: ${svc}" \
                || { log "ERROR" "RESTART" "Apache reload FAILED"; return 1; }
            ;;

        none)
            log "INFO" "RESTART" "WEBSERVER=none — skipping web server reload"
            ;;

        *)
            log "WARN" "RESTART" "Unknown WEBSERVER: ${webserver} — skipping"
            ;;
    esac
}

# ── Public entry point ────────────────────────────────────────────────────────
module_restart_services() {
    _restart_app_server
    _reload_web_server
    log "OK" "RESTART" "All services restarted/reloaded"
}
