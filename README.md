<div align="center">

# Automated Deployment Pipeline

**Zero-downtime, multi-environment deployments for Node.js, Python, PHP, and static sites — in pure Bash.**

<p>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/OS-RHEL%209%20%7C%20Ubuntu%2022.04%2B-CC0000?style=flat-square&logo=redhat&logoColor=white" alt="RHEL9 / Ubuntu">
  <img src="https://img.shields.io/badge/Tests-9%2F9%20Passing-brightgreen?style=flat-square&logo=checkmarx&logoColor=white" alt="Tests 9/9 Passing">
  <img src="https://img.shields.io/badge/Version-1.0.0-orange?style=flat-square" alt="v1.0.0">
</p>

[Live Demo Page](https://samiulasumel.github.io/auto-deploy-pipeline/) &nbsp;|&nbsp;
[View on GitHub](https://github.com/samiulAsumel/auto-deploy-pipeline) &nbsp;|&nbsp;
[Changelog](CHANGELOG.md)

</div>

---

## Overview

`auto-deploy-pipeline` is a production-ready, zero-dependency deployment system written entirely in Bash. It runs a structured **9-step pipeline** — from pre-flight safety checks to Slack notifications — across three environments (`production`, `staging`, `dev`). Every deploy is atomic: a single `ln -sfn` syscall makes the new release live, so downtime is measured in microseconds. If the post-deploy health check fails, the pipeline automatically reverts to the previous release without human intervention.

No Docker, no Ansible, no CI/CD agent required. If your server has `bash`, `git`, and `curl`, you can deploy.

---

## Terminal Demo

```
╔══════════════════════════════════════════════════════════════════╗
║    Automated Deployment Pipeline  —  v1.0.0                      ║
║    RHEL 9 / Ubuntu Server  ·  Node.js · Python · PHP · Static    ║
╚══════════════════════════════════════════════════════════════════╝

[2026-05-30 09:15:00] [DEPLOY] [STEP] ━━━ Step 1: PRE-FLIGHT CHECKS ━━━
[2026-05-30 09:15:01] [PRE]    [OK]   Disk: 18432 MB free (need 2048 MB)
[2026-05-30 09:15:01] [PRE]    [OK]   Git reachable: git@github.com:company/app.git
[2026-05-30 09:15:01] [PRE]    [OK]   DB reachable: localhost:5432
[2026-05-30 09:15:01] [PRE]    [OK]   Tools present: git curl node npm

[2026-05-30 09:15:02] [DEPLOY] [STEP] ━━━ Step 2: BACKUP CURRENT VERSION ━━━
[2026-05-30 09:15:02] [BACKUP] [OK]   Previous release recorded: /var/www/releases/20260529-143021

[2026-05-30 09:15:02] [DEPLOY] [STEP] ━━━ Step 3: PULL CODE ━━━
[2026-05-30 09:15:04] [PULL]   [OK]   Cloned branch main → /var/www/releases/20260530-091500
[2026-05-30 09:15:04] [PULL]   [OK]   Linked shared: .env storage uploads
[2026-05-30 09:15:09] [PULL]   [OK]   npm ci complete (312 packages)
[2026-05-30 09:15:11] [PULL]   [OK]   Build complete: npm run build

[2026-05-30 09:15:11] [DEPLOY] [STEP] ━━━ Step 4: RUN TESTS ━━━
[2026-05-30 09:15:14] [TEST]   [OK]   Tests passed in 3s

[2026-05-30 09:15:14] [DEPLOY] [STEP] ━━━ Step 5: SWITCH VERSION ━━━
[2026-05-30 09:15:14] [SWITCH] [OK]   Atomic symlink: /var/www/current → releases/20260530-091500

[2026-05-30 09:15:15] [DEPLOY] [STEP] ━━━ Step 6: RESTART SERVICES ━━━
[2026-05-30 09:15:15] [SVC]    [OK]   pm2 reload myapp — 0 downtime
[2026-05-30 09:15:15] [SVC]    [OK]   nginx config test passed; nginx reloaded

[2026-05-30 09:15:15] [DEPLOY] [STEP] ━━━ Step 7: VERIFY DEPLOYMENT ━━━
[2026-05-30 09:15:25] [VERIFY] [OK]   Health check HTTP 200 — http://localhost:3000/health

[2026-05-30 09:15:25] [DEPLOY] [STEP] ━━━ Step 8: CLEANUP OLD RELEASES ━━━
[2026-05-30 09:15:25] [CLEAN]  [OK]   Removed old release: 20260525-080001

[2026-05-30 09:15:25] [DEPLOY] [STEP] ━━━ Step 9: NOTIFY ━━━
[2026-05-30 09:15:25] [NOTIFY] [OK]   Slack notification sent (success)

══════ Deploy Complete ══════
  App:         myapp
  Environment: production
  Deploy ID:   20260530-091500
  Release:     /var/www/releases/20260530-091500
  Duration:    25s
  Log:         /var/log/deploys/20260530-091500.log
```

---

## Features

- **9-step structured pipeline** with per-step logging and isolated failure handling
- **Atomic version switching** via `ln -sfn` — zero downtime, single syscall
- **Automatic rollback** — reverts the symlink and restarts services if the health check fails
- **Multi-environment support** — `production`, `staging`, `dev` configs with override layering
- **Multi-stack support** — Node.js (`pm2`), Python (`gunicorn`), PHP (`php-fpm`), static sites
- **Web server integration** — nginx (config test + reload) and Apache (`graceful` restart)
- **Pre-flight checks** — disk space, git reachability, database connectivity, required tools
- **Shared directory** — `.env`, `uploads`, `storage` persisted across releases with symlinks
- **Release retention** — configurable `KEEP_RELEASES` (default 5); older releases auto-pruned
- **Slack notifications** — colour-coded attachments (green/red/orange) with deploy metadata
- **Email notifications** — via `mailx`, `mail`, or `sendmail`
- **Dry-run mode** — preview every action without touching the server
- **Lock file** — prevents concurrent deploys; detects and removes stale locks
- **Structured logging** — timestamped, per-deploy log files with automatic rotation
- **One-command installer** — creates directories, installs configs, sets up logrotate
- **9 unit tests** — all pass without a live server or real repository

---

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/samiulAsumel/auto-deploy-pipeline.git
cd auto-deploy-pipeline

# 2. Install (creates dirs, installs scripts, configures logrotate)
sudo bash install.sh

# 3. Edit config, then deploy
sudo nano /etc/autodeploy/config.conf
sudo deploy production
```

After installation the `deploy` command is available system-wide at `/usr/local/bin/deploy`.

---

## Deployment Pipeline

Each `deploy` invocation runs these steps in order. Any step failure aborts the pipeline (and triggers auto-rollback if the version was already switched).

| Step | Name | What Happens |
|------|------|--------------|
| 1 | **Pre-Flight Checks** | Verify free disk space (`MIN_DISK_MB`), git remote reachability, DB connectivity (`DB_HOST:DB_PORT`), required tools |
| 2 | **Backup Current** | Resolve `current` symlink target and write it to the rollback state file |
| 3 | **Pull Code** | `git clone --depth 1` into a timestamped release dir; link shared `.env`/`uploads`/`storage`; run `npm ci` / `pip install` / `composer install`; run build command |
| 4 | **Run Tests** | Execute `TEST_CMD` with a `TEST_TIMEOUT` watchdog; abort deploy if tests fail (no production change made yet) |
| 5 | **Switch Version** | `ln -sfn <release_dir> /var/www/current` — atomic, zero-downtime cutover |
| 6 | **Restart Services** | `pm2 reload` / `systemctl restart gunicorn` / `php-fpm reload` + `nginx -t && nginx -s reload` / `apache2ctl graceful` |
| 7 | **Verify Deployment** | Poll `HEALTH_URL` up to `HEALTH_RETRIES` times; trigger auto-rollback on failure |
| 8 | **Cleanup Releases** | Delete oldest release directories, keeping the last `KEEP_RELEASES` |
| 9 | **Notify** | Send Slack webhook (colour-coded) and/or email with deploy metadata |

---

## Project Structure

```
auto-deploy-pipeline/
├── deploy.sh                  # Main orchestrator — parses args, sources libs, runs 9 steps
├── config.conf                # Central configuration (all settings with inline docs)
├── config.production.conf     # Production environment overrides
├── config.staging.conf        # Staging environment overrides
├── config.dev.conf            # Development environment overrides
├── install.sh                 # One-command installer with uninstall mode and dry-run
├── lib/
│   ├── pre_deploy.sh          # Step 1 — disk/git/DB/tool pre-flight checks
│   ├── backup_current.sh      # Step 2 — records previous release path to state file
│   ├── pull_code.sh           # Step 3 — git clone, shared file links, install deps, build
│   ├── run_tests.sh           # Step 4 — test suite runner with configurable timeout
│   ├── switch_version.sh      # Step 5 — atomic ln -sfn symlink switch
│   ├── restart_services.sh    # Step 6 — pm2/gunicorn/php-fpm + nginx/apache
│   ├── verify_deploy.sh       # Step 7 — HTTP health check with retries
│   ├── rollback.sh            # Restore symlink, restart services, re-verify, clear state
│   └── notify_deploy.sh       # Slack webhook + email notifications
├── scripts/
│   └── cleanup_releases.sh    # Standalone utility to prune old releases manually
└── tests/
    └── test_deploy.sh         # 9 unit tests (all passing, no live server needed)
```

---

## Configuration Reference

All settings live in `config.conf` and are overridden per environment. After installation configs are at `/etc/autodeploy/`.

### Application Identity

| Setting | Default | Description |
|---------|---------|-------------|
| `APP_NAME` | `myapp` | Application name (used in notifications and pm2) |
| `APP_USER` | `appuser` | OS user that owns deployed files |
| `APP_GROUP` | `appuser` | OS group for deployed files |
| `REPO_URL` | — | Git remote URL (SSH or HTTPS) |
| `BRANCH` | `main` | Branch, tag, or commit SHA to deploy |

### Directory Layout

| Setting | Default | Description |
|---------|---------|-------------|
| `DEPLOY_BASE` | `/var/www` | Root deployment directory |
| `RELEASES_DIR` | `/var/www/releases` | Parent directory for timestamped release dirs |
| `CURRENT_LINK` | `/var/www/current` | Symlink pointing to the active release |
| `SHARED_DIR` | `/var/www/shared` | Persistent files shared across releases |

### Application Stack

| Setting | Options | Description |
|---------|---------|-------------|
| `APP_TYPE` | `nodejs` `python` `php` `static` | Controls which dependency installer runs |
| `APP_SERVER` | `pm2` `gunicorn` `php-fpm` `none` | Process manager to reload on deploy |
| `WEBSERVER` | `nginx` `apache` `none` | Web server to reload after service restart |

### Build and Tests

| Setting | Default | Description |
|---------|---------|-------------|
| `BUILD_ENABLED` | `true` | Run a build command after installing dependencies |
| `BUILD_CMD` | `npm run build` | Command to execute in the release directory |
| `RUN_TESTS` | `true` | Run the test suite before switching versions |
| `TEST_CMD` | `npm test` | Test command (must exit 0 on success) |
| `TEST_TIMEOUT` | `300` | Seconds before the test run is killed |

### Health Check

| Setting | Default | Description |
|---------|---------|-------------|
| `HEALTH_URL` | `http://localhost:3000/health` | Endpoint polled after deploy to verify success |
| `HEALTH_RETRIES` | `3` | Number of attempts before marking the deploy failed |
| `HEALTH_RETRY_INTERVAL` | `10` | Seconds to wait between retry attempts |
| `HEALTH_WARMUP` | `10` | Seconds to wait before the first health check |

### Rollback and Release Management

| Setting | Default | Description |
|---------|---------|-------------|
| `AUTO_ROLLBACK` | `true` | Automatically roll back if health check fails |
| `KEEP_RELEASES` | `5` | Number of recent release directories to retain |
| `ROLLBACK_STATE_FILE` | `/tmp/deploy_previous` | File storing the previous release path |

### Notifications

| Setting | Options / Default | Description |
|---------|-------------------|-------------|
| `NOTIFY_METHOD` | `slack` `email` `both` `none` | Which channel(s) to use |
| `NOTIFY_ON` | `success` `failure` `both` | When to send notifications |
| `SLACK_WEBHOOK` | `""` | Full Slack Incoming Webhook URL |
| `NOTIFY_EMAIL` | `devops@company.com` | Recipient address for email alerts |

### Logging

| Setting | Default | Description |
|---------|---------|-------------|
| `LOG_DIR` | `/var/log/deploys` | Directory for per-deploy log files |
| `LOG_MAX_DAYS` | `30` | Delete log files older than this many days |

### Database (Pre-flight)

| Setting | Default | Description |
|---------|---------|-------------|
| `CHECK_DB` | `true` | Verify DB reachability before deploy |
| `DB_HOST` | `localhost` | Database host |
| `DB_PORT` | `5432` | Database port (3306 for MySQL, 5432 for PostgreSQL) |
| `DB_MIGRATE` | `false` | Run `DB_MIGRATE_CMD` after a successful deploy |
| `DB_MIGRATE_CMD` | `npm run db:migrate` | Migration command |

---

## Multi-Environment Support

Configuration is layered: `config.conf` provides defaults, and the environment-specific file overrides only what differs.

```
config.conf                 ← shared defaults (always loaded)
config.production.conf      ← production overrides  (loaded for: sudo deploy production)
config.staging.conf         ← staging overrides     (loaded for: sudo deploy staging)
config.dev.conf             ← dev overrides         (loaded for: sudo deploy dev)
```

**Example** — `config.staging.conf`:

```bash
BRANCH="develop"
HEALTH_URL="http://localhost:3001/health"
KEEP_RELEASES=2
NOTIFY_METHOD="none"
AUTO_ROLLBACK=false
```

**Example** — `config.production.conf`:

```bash
BRANCH="main"
MIN_DISK_MB=4096
HEALTH_URL="https://myapp.com/health"
NOTIFY_METHOD="both"
SLACK_WEBHOOK="https://hooks.slack.com/services/T00/B00/xxxx"
NOTIFY_EMAIL="devops@company.com"
```

---

## Usage Examples

```bash
# Full production deploy
sudo deploy production

# Preview all actions without making any changes
sudo deploy production --dry-run --verbose

# Deploy to staging, skipping the test suite
sudo deploy staging --skip-tests

# Deploy to dev with verbose output
sudo deploy dev --verbose

# Manually trigger a rollback to the previous release
sudo deploy production --rollback

# Prune old releases, keeping only the last 3
bash scripts/cleanup_releases.sh --keep=3

# Run the full unit test suite
bash tests/test_deploy.sh
```

**Post-install commands:**

```bash
# View a live deploy log
tail -f /var/log/deploys/<DEPLOY_ID>.log

# Check the current active release
readlink /var/www/current

# List all releases
ls -lt /var/www/releases/

# Run installer in preview mode (no changes)
sudo bash install.sh --dry-run

# Remove the pipeline from the system
sudo bash install.sh --uninstall
```

---

## Rollback

Rollback restores the previous release symlink, reloads services, re-runs the health check, and clears the rollback state file.

### Automatic Rollback

When `AUTO_ROLLBACK=true` (the default), Step 7 (Verify Deployment) triggers a full rollback automatically if the health check fails after all retries are exhausted. A Slack/email notification is sent with the rollback reason.

### Manual Rollback

```bash
sudo deploy production --rollback
```

This reads the path saved in `ROLLBACK_STATE_FILE` (written during Step 2 of the last deploy), switches the symlink back, and restarts services. The previous release must still exist on disk (i.e., within `KEEP_RELEASES`).

### Rollback Flow

```
Read ROLLBACK_STATE_FILE
        │
        ▼
ln -sfn <previous_release> /var/www/current
        │
        ▼
Reload services (pm2 / gunicorn / php-fpm + nginx / apache)
        │
        ▼
Re-run health check
        │
        ▼
Clear ROLLBACK_STATE_FILE + send notification
```

---

## Notifications Setup

### Slack

1. Create an [Incoming Webhook](https://api.slack.com/messaging/webhooks) in your Slack workspace.
2. Set the webhook URL in your config:

```bash
SLACK_WEBHOOK="https://hooks.slack.com/services/T00000000/B00000000/xxxxxxxxxxxxxxxx"
NOTIFY_METHOD="slack"    # or "both" for Slack + email
NOTIFY_ON="both"         # success | failure | both
```

Slack messages include: status (colour-coded green/red/orange), app name, environment, deploy ID, branch, git commit SHA, deploying user, and server hostname.

### Email

Ensure `mailx`, `mail`, or `sendmail` is installed on the server:

```bash
# RHEL / Rocky Linux
sudo dnf install mailx -y

# Ubuntu
sudo apt install mailutils -y
```

Then configure:

```bash
NOTIFY_EMAIL="devops@company.com"
NOTIFY_METHOD="email"    # or "both"
```

### Disable Notifications

```bash
NOTIFY_METHOD="none"
```

---

## Deployed Directory Layout

After the first deploy, the web root looks like this:

```
/var/www/
├── releases/
│   ├── 20260528-110045/        # older release (pruned after KEEP_RELEASES exceeded)
│   ├── 20260529-143021/        # previous release (available for rollback)
│   └── 20260530-091500/        # current release
├── current -> releases/20260530-091500/   # atomic symlink (the live version)
└── shared/
    ├── .env                    # environment variables (never deleted)
    ├── storage/                # application storage (never deleted)
    └── uploads/                # user uploads (never deleted)
```

Point your web server or process manager at `/var/www/current`. The symlink is updated atomically on each deploy — nginx and Apache serve the new version the instant the syscall completes.

---

## Running Tests

The test suite exercises all core modules using a temporary directory. No live server, database, or real repository is required.

```bash
bash tests/test_deploy.sh
```

**Expected output:**

```
═══════════════════════════════════════
  auto-deploy-pipeline — Unit Tests
═══════════════════════════════════════

── backup_current ──
  PASS: first deploy writes empty state file
  PASS: records previous release path

── switch_version ──
  PASS: symlink points to RELEASE_DIR

── verify_deploy (HEALTH_URL empty → skip) ──
  PASS: module_verify_deploy exits 0

── verify_deploy (HTTP 200 mock) ──
  PASS: module_verify_deploy exits 0

── rollback ──
  PASS: rollback restores previous symlink
  PASS: module_rollback no-state correctly failed
  PASS: module_rollback empty-state correctly failed

── notify_deploy (NOTIFY_METHOD=none) ──
  PASS: _notify_deploy success test message exits 0

═══════════════════════════════════════
  PASSED: 9   FAILED: 0   SKIPPED: 0
═══════════════════════════════════════
```

The suite exits `0` on all pass, non-zero on any failure. Integrate it into CI by running `bash tests/test_deploy.sh` as a pipeline step.

---

## Requirements

### Required (always)

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| `bash` | 4.0+ | Script runtime (`mapfile`, `[[ ]]`, `set -euo pipefail`) |
| `git` | 2.x | Cloning repositories |
| `curl` | any | Health checks and Slack webhook delivery |
| `date`, `find`, `ln` | coreutils | Deploy ID, release cleanup, atomic symlink |

### Optional (feature-dependent)

| Tool | Feature |
|------|---------|
| `node` / `npm` | Node.js app builds (`npm ci`, `npm run build`) |
| `python3` / `pip3` | Python app installs (`pip install -r requirements.txt`) |
| `php` / `composer` | PHP app installs (`composer install --no-dev`) |
| `pm2` | Node.js process management (zero-downtime reload) |
| `gunicorn` | Python WSGI process management |
| `php-fpm` | PHP-FPM process management |
| `nginx` | Web server reload after deploy |
| `httpd` / `apache2` | Apache web server graceful restart |
| `mailx` / `mail` / `sendmail` | Email notifications |
| `nc` (netcat) | Database port reachability pre-flight check |
| `timeout` | Test suite watchdog timer |

### Supported Operating Systems

| Distribution | Status |
|-------------|--------|
| RHEL 9 | Fully supported |
| Rocky Linux 9 | Fully supported |
| AlmaLinux 9 | Fully supported |
| Ubuntu Server 22.04 LTS | Fully supported |
| Ubuntu Server 24.04 LTS | Fully supported |
| Debian 12 | Supported (community-tested) |

---

## License

Released under the [MIT License](LICENSE).

```
MIT License — Copyright (c) 2026 samiulAsumel

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```

---

<div align="center">

Built with pure Bash &mdash; no agents, no containers, no magic.

[GitHub](https://github.com/samiulAsumel/auto-deploy-pipeline) &nbsp;|&nbsp;
[Project Page](https://samiulasumel.github.io/auto-deploy-pipeline/) &nbsp;|&nbsp;
[Changelog](CHANGELOG.md)

</div>
