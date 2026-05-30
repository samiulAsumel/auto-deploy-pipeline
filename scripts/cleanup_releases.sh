#!/usr/bin/env bash
# scripts/cleanup_releases.sh — Manual release cleanup utility  v1.0.0
# Lists releases and removes old ones beyond KEEP_RELEASES limit.
# Usage: bash cleanup_releases.sh [--dry-run] [--keep=N]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.conf"
[[ -f "$CONFIG_FILE" ]] || { echo "[FATAL] config.conf not found" >&2; exit 1; }
# shellcheck source=../config.conf
source "$CONFIG_FILE"

DRY_RUN=false; KEEP="${KEEP_RELEASES:-5}"

for _arg in "$@"; do
    case "$_arg" in
        --dry-run)  DRY_RUN=true ;;
        --keep=*)   KEEP="${_arg#*=}" ;;
    esac
done

echo "Releases directory: ${RELEASES_DIR}"
echo "Keeping last ${KEEP} releases"
echo ""

if [[ ! -d "$RELEASES_DIR" ]]; then
    echo "[INFO] No releases directory found: ${RELEASES_DIR}"
    exit 0
fi

mapfile -t all_releases < <(
    find "$RELEASES_DIR" -maxdepth 1 -mindepth 1 -type d | sort
)

total=${#all_releases[@]}
echo "Total releases: ${total}"

if (( total <= KEEP )); then
    echo "[OK] Nothing to clean — ${total} releases ≤ keep limit ${KEEP}"
    exit 0
fi

echo ""
echo "Releases to remove:"
mapfile -t to_remove < <(printf '%s\n' "${all_releases[@]}" | head -n "$(( total - KEEP ))")

for dir in "${to_remove[@]}"; do
    echo "  REMOVE: $(basename "$dir")"
    $DRY_RUN || rm -rf "$dir"
done

echo ""
echo "Releases to keep:"
mapfile -t to_keep < <(printf '%s\n' "${all_releases[@]}" | tail -n "$KEEP")
for dir in "${to_keep[@]}"; do
    local_current=""
    [[ -L "${CURRENT_LINK:-/var/www/current}" ]] && \
        local_current=$(readlink "${CURRENT_LINK:-/var/www/current}" 2>/dev/null || true)
    marker=""
    [[ "$dir" == "$local_current" ]] && marker=" ← CURRENT"
    echo "  KEEP:   $(basename "$dir")${marker}"
done

echo ""
$DRY_RUN && echo "[DRY-RUN] No changes made" || echo "[OK] Cleanup complete"
