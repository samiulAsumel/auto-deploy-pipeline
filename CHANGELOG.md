# Changelog — Automated Deployment Pipeline

All notable changes are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.0.0] — 2026-05-30

### Added
- `deploy.sh` — main orchestrator with 9-step pipeline, lock file, dry-run, verbose, skip-tests, and rollback flags
- `lib/pre_deploy.sh` — pre-flight checks: disk space, git access, DB connection, tool detection, directory creation
- `lib/backup_current.sh` — records current release path to state file for rollback
- `lib/pull_code.sh` — git clone, shared file linking, npm/pip/composer install, build step
- `lib/run_tests.sh` — test suite runner with configurable timeout and streaming log output
- `lib/switch_version.sh` — atomic `ln -sfn` symlink switch with verification
- `lib/restart_services.sh` — pm2 reload/restart, gunicorn, php-fpm, nginx config test + reload, apache graceful
- `lib/verify_deploy.sh` — HTTP health check with configurable retries and warmup delay
- `lib/rollback.sh` — full rollback: symlink restore, service restart, health verify, state file clear
- `lib/notify_deploy.sh` — Slack webhook (colour-coded attachments) and email notifications
- `config.conf` — central configuration with all settings documented
- `config.production.conf` / `config.staging.conf` / `config.dev.conf` — per-environment overrides
- `install.sh` — one-command installer with directory creation, script install, logrotate, dry-run validation, uninstall mode
- `scripts/cleanup_releases.sh` — manual release cleanup utility with --keep=N override
- `tests/test_deploy.sh` — unit tests for all modules using a temp directory; no live server required
- `index.html` + `style.css` + `scripts-data.js` + `favicon.svg` — GitHub Pages landing page with script explorer, flow steps, rollback demo, environment table, and deploy playground
