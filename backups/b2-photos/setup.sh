#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${HOME}/.config/.env"
RCLONE_CONF="${HOME}/.config/rclone/rclone.conf"
BUCKET="hamzilla-backups"

info() { echo "[INFO] $*"; }
error() { echo "[ERROR] $*" >&2; }

# --- Load credentials ---
if [[ ! -f "$ENV_FILE" ]]; then
    error "Env file not found: $ENV_FILE"
    error "Backblaze credentials are stored in 1Password (UUID: 4gy3y7zex57wcftxkjrtnazqoy)"
    exit 1
fi

source "$ENV_FILE"

if [[ -z "${BACKBLAZE_KEY_ID:-}" || -z "${BACKBLAZE_APP_KEY:-}" ]]; then
    error "BACKBLAZE_KEY_ID or BACKBLAZE_APP_KEY not set in $ENV_FILE"
    exit 1
fi

# --- Install rclone if missing ---
if ! command -v rclone &>/dev/null; then
    info "rclone not found. Installing..."
    curl -O https://downloads.rclone.org/current/rclone-current-linux-amd64.zip
    unzip -o rclone-current-linux-amd64.zip
    cp rclone-*-linux-amd64/rclone /usr/local/bin/
    chmod +x /usr/local/bin/rclone
    rm -rf rclone-current-linux-amd64.zip rclone-*-linux-amd64
    info "rclone installed: $(rclone version | head -1)"
else
    info "rclone already installed: $(rclone version | head -1)"
fi

# --- Create rclone config directory ---
mkdir -p "$(dirname "$RCLONE_CONF")"

# --- Check if already configured ---
if [[ -f "$RCLONE_CONF" ]] && grep -q "^\[b2\]" "$RCLONE_CONF" && grep -q "^\[b2crypt\]" "$RCLONE_CONF"; then
    info "rclone remotes 'b2' and 'b2crypt' already configured."
    info "To reconfigure, delete $RCLONE_CONF and re-run this script."
    exit 0
fi

# --- Configure B2 remote ---
info "Configuring B2 remote..."
cat >> "$RCLONE_CONF" <<EOF

[b2]
type = b2
account = ${BACKBLAZE_KEY_ID}
key = ${BACKBLAZE_APP_KEY}
EOF

# --- Configure crypt remote ---
info "Configuring crypt remote (b2crypt)..."
echo ""
echo "You need an encryption password for client-side encryption."
echo "This password encrypts your files before they leave the Synology."
echo "STORE IT SAFELY -- if you lose it, your backed-up files are unrecoverable."
echo ""
read -rsp "Enter encryption password: " PASS1; echo
read -rsp "Confirm encryption password: " PASS2; echo

if [[ "$PASS1" != "$PASS2" ]]; then
    error "Passwords do not match."
    exit 1
fi

if [[ ${#PASS1} -lt 8 ]]; then
    error "Password must be at least 8 characters."
    exit 1
fi

# Use rclone obscure to store the password
OBS_PASS=$(rclone obscure "$PASS1")
OBS_SALT=$(rclone obscure "$(echo "$PASS1" | sha256sum | head -c 32)")

cat >> "$RCLONE_CONF" <<EOF

[b2crypt]
type = crypt
remote = b2:${BUCKET}
password = ${OBS_PASS}
password2 = ${OBS_SALT}
EOF

chmod 600 "$RCLONE_CONF"

info "Configuration written to $RCLONE_CONF"
info "Testing connectivity..."

if rclone lsd b2:${BUCKET} --max-depth 0 2>/dev/null; then
    info "Successfully connected to B2 bucket '${BUCKET}'."
else
    info "Bucket '${BUCKET}' may not exist yet. rclone will create it on first upload."
fi

info "Setup complete. Run './backup.sh' to start your first backup."
