#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/var/log/hamzilla-services"
LOG_FILE="$LOG_DIR/b2-photo-backup.log"
TRANSFERS=4
CHECKERS=8

PHOTO_DIRS=(
    "/volume1/homes/hamzilla/Photos|hamzilla-photos"
    "/volume1/homes/salwabalwa/Photos|salwabalwa-photos"
)

EXCLUDES=(
    "--exclude" ".DS_Store"
    "--exclude" "Thumbs.db"
    "--exclude" "._*"
    "--exclude" ".AppleDouble"
)

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

error() { log "[ERROR] $*"; }

# --- Preflight ---
mkdir -p "$LOG_DIR"

if ! command -v rclone &>/dev/null; then
    error "rclone not found. Run setup.sh first."
    exit 1
fi

if ! rclone listremotes 2>/dev/null | grep -q "^b2crypt:"; then
    error "rclone remote 'b2crypt' not configured. Run setup.sh first."
    exit 1
fi

log "=== B2 Photo Backup Started ==="

FAILED=0
for entry in "${PHOTO_DIRS[@]}"; do
    IFS='|' read -r src_dir dest_name <<< "$entry"

    if [[ ! -d "$src_dir" ]]; then
        error "Source directory does not exist: $src_dir"
        FAILED=1
        continue
    fi

    log "Syncing $src_dir -> b2crypt:${dest_name}/"

    if rclone sync "$src_dir" "b2crypt:${dest_name}/" \
        --transfers "$TRANSFERS" \
        --checkers "$CHECKERS" \
        "${EXCLUDES[@]}" \
        --log-level INFO \
        --log-file "$LOG_FILE" \
        --stats-one-line \
        --stats 30s; then
        log "Completed: $src_dir"
    else
        error "Failed: $src_dir"
        FAILED=1
    fi
done

if [[ $FAILED -ne 0 ]]; then
    error "One or more syncs failed. Check $LOG_FILE"
    log "=== B2 Photo Backup Finished (with errors) ==="
    exit 1
fi

log "=== B2 Photo Backup Finished Successfully ==="
