#!/usr/bin/env bash
set -euo pipefail

RESTORE_DIR="./restored"

info() { echo "[INFO] $*"; }
error() { echo "[ERROR] $*" >&2; }

check_rclone() {
    if ! command -v rclone &>/dev/null; then
        error "rclone not found. Run setup.sh first."
        exit 1
    fi
    if ! rclone listremotes 2>/dev/null | grep -q "^b2crypt:"; then
        error "rclone remote 'b2crypt' not configured. Run setup.sh first."
        exit 1
    fi
}

list_top_level() {
    echo ""
    echo "=== Contents of b2crypt: ==="
    rclone lsd b2crypt: 2>/dev/null | awk '{print $NF}' | sed 's/^/  /'
    echo ""
}

browse_folder() {
    local folder="$1"
    echo ""
    echo "=== Contents of b2crypt:${folder}/ ==="
    rclone ls "b2crypt:${folder}" --max-depth 1 2>/dev/null | head -50
    local count
    count=$(rclone ls "b2crypt:${folder}" --max-depth 1 2>/dev/null | wc -l)
    if [[ $count -gt 50 ]]; then
        echo "  ... and $((count - 50)) more items"
    fi
    echo ""
}

search_files() {
    local pattern="$1"
    echo ""
    echo "=== Searching for '${pattern}' ==="
    rclone ls b2crypt: --include "*${pattern}*" 2>/dev/null | head -50
    local count
    count=$(rclone ls b2crypt: --include "*${pattern}*" 2>/dev/null | wc -l)
    if [[ $count -gt 50 ]]; then
        echo "  ... and $((count - 50)) more matches"
    fi
    echo ""
}

download_folder() {
    local folder="$1"
    local dest="${RESTORE_DIR}/${folder}"
    mkdir -p "$dest"
    info "Downloading b2crypt:${folder}/ -> ${dest}/"
    rclone copy "b2crypt:${folder}" "$dest" --transfers 4 --progress
    info "Download complete: ${dest}/"
}

download_file() {
    local filepath="$1"
    local dir
    dir=$(dirname "$filepath")
    mkdir -p "${RESTORE_DIR}/${dir}"
    info "Downloading b2crypt:${filepath} -> ${RESTORE_DIR}/${filepath}"
    rclone copyto "b2crypt:${filepath}" "${RESTORE_DIR}/${filepath}" --progress
    info "Download complete."
}

download_all() {
    mkdir -p "$RESTORE_DIR"
    info "Downloading all files from b2crypt: -> ${RESTORE_DIR}/"
    rclone copy b2crypt: "$RESTORE_DIR" --transfers 4 --progress
    info "Full restore complete: ${RESTORE_DIR}/"
}

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [command] [args]

Commands:
  list                        List top-level folders in the bucket
  browse <folder>             Show contents of a folder
  search <pattern>            Search for files by name
  download-folder <folder>    Download an entire folder
  download-file <path>        Download a single file
  download-all                Download everything
  interactive                 Interactive menu (default)

Examples:
  $(basename "$0") list
  $(basename "$0") browse hamzilla-photos
  $(basename "$0") search ".jpg"
  $(basename "$0") download-folder hamzilla-photos/2024
  $(basename "$0") download-file hamzilla-photos/2024/vacation/photo1.jpg
EOF
}

interactive_menu() {
    while true; do
        echo ""
        echo "╔══════════════════════════════════╗"
        echo "║   B2 Photo Restore Tool          ║"
        echo "╠══════════════════════════════════╣"
        echo "║  1) List folders                 ║"
        echo "║  2) Browse a folder              ║"
        echo "║  3) Search for files             ║"
        echo "║  4) Download a folder            ║"
        echo "║  5) Download a file              ║"
        echo "║  6) Download everything          ║"
        echo "║  7) Change restore directory     ║"
        echo "║  q) Quit                         ║"
        echo "╚══════════════════════════════════╝"
        echo ""
        echo "Restore directory: ${RESTORE_DIR}"
        echo ""
        read -rp "Choice: " choice

        case "$choice" in
            1) list_top_level ;;
            2)
                read -rp "Folder name: " folder
                browse_folder "$folder"
                ;;
            3)
                read -rp "Search pattern: " pattern
                search_files "$pattern"
                ;;
            4)
                read -rp "Folder to download: " folder
                download_folder "$folder"
                ;;
            5)
                read -rp "File path (e.g. hamzilla-photos/2024/photo.jpg): " filepath
                download_file "$filepath"
                ;;
            6)
                read -rp "Download ALL files? This may take a while. [y/N] " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] && download_all
                ;;
            7)
                read -rp "New restore directory: " newdir
                RESTORE_DIR="$newdir"
                info "Restore directory set to: ${RESTORE_DIR}"
                ;;
            q|Q) echo "Bye."; exit 0 ;;
            *) error "Invalid choice." ;;
        esac
    done
}

# --- Main ---
check_rclone

if [[ $# -eq 0 ]]; then
    interactive_menu
    exit 0
fi

case "${1:-}" in
    list)           list_top_level ;;
    browse)         shift; browse_folder "${1:?Usage: $0 browse <folder>}" ;;
    search)         shift; search_files "${1:?Usage: $0 search <pattern>}" ;;
    download-folder) shift; download_folder "${1:?Usage: $0 download-folder <folder>}" ;;
    download-file)  shift; download_file "${1:?Usage: $0 download-file <path>}" ;;
    download-all)   download_all ;;
    interactive)    interactive_menu ;;
    -h|--help)      show_usage ;;
    *)              error "Unknown command: $1"; show_usage; exit 1 ;;
esac
