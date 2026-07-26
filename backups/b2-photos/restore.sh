#!/usr/bin/env bash
set -euo pipefail

RESTORE_DIR="./restored"
CURRENT_PATH=""

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

human_size() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        printf "%.1fG" "$(echo "$bytes / 1073741824" | bc -l)"
    elif (( bytes >= 1048576 )); then
        printf "%.1fM" "$(echo "$bytes / 1048576" | bc -l)"
    elif (( bytes >= 1024 )); then
        printf "%.1fK" "$(echo "$bytes / 1024" | bc -l)"
    else
        printf "%dB" "$bytes"
    fi
}

# Build rclone path from current path
rc_path() {
    if [[ -n "$CURRENT_PATH" ]]; then
        echo "b2crypt:${CURRENT_PATH}"
    else
        echo "b2crypt:"
    fi
}

# Resolve a user-supplied path relative to current
resolve_path() {
    local input="$1"
    local path="$CURRENT_PATH"

    # Handle absolute paths
    if [[ "$input" == /* ]]; then
        path="${input#/}"
        path="${path%/}"
        echo "$path"
        return
    fi

    # Handle relative paths with ../
    IFS='/' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
        [[ -z "$part" ]] && continue
        if [[ "$part" == ".." ]]; then
            path="${path%/*}"
        elif [[ "$part" != "." ]]; then
            [[ -n "$path" ]] && path="${path}/${part}" || path="$part"
        fi
    done

    echo "$path"
}

cmd_ls() {
    local long=false
    local target=""

    # Parse args from raw string: -l flag and target path
    local raw="$*"
    if [[ "$raw" == -l\ * ]]; then
        long=true
        target="${raw#-l }"
    elif [[ "$raw" == "-l" ]]; then
        long=true
    elif [[ -n "$raw" && "$raw" != "." ]]; then
        target="$raw"
    fi

    # Strip trailing slash from target
    target="${target%/}"

    local rc
    if [[ -n "$target" ]]; then
        local resolved
        resolved=$(resolve_path "$target")
        rc="b2crypt:${resolved}"
    else
        rc=$(rc_path)
    fi

    # Get directories (use lsf for reliable name parsing)
    local dirs=()
    while IFS= read -r d; do
        [[ -n "$d" ]] && dirs+=("$d")
    done < <(rclone lsf "$rc" --dirs-only 2>/dev/null | sed 's|/$||')

    # Get files with sizes
    local files_raw=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && files_raw+=("$line")
    done < <(rclone lsl "$rc" --max-depth 1 2>/dev/null | grep -v '/$' || true)

    if [[ ${#dirs[@]} -eq 0 && ${#files_raw[@]} -eq 0 ]]; then
        echo "(empty)"
        return
    fi

    # Print directories
    for d in "${dirs[@]+"${dirs[@]}"}"; do
        [[ -z "$d" ]] && continue
        if $long; then
            local count
            count=$(rclone ls "${rc}/${d}" 2>/dev/null | wc -l | tr -d ' ')
            printf "  \033[1;34m%-40s\033[0m  %s items\n" "${d}/" "$count"
        else
            printf "  \033[1;34m%s/\033[0m\n" "$d"
        fi
    done

    # Print files
    for line in "${files_raw[@]+"${files_raw[@]}"}"; do
        [[ -z "$line" ]] && continue
        local size name
        size=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | cut -d' ' -f4-)
        if $long; then
            printf "  %-40s  %s\n" "$name" "$(human_size "$size")"
        else
            printf "  %s\n" "$name"
        fi
    done
}

cmd_cd() {
    local input="$1"

    if [[ "$input" == "/" || "$input" == "~" ]]; then
        CURRENT_PATH=""
        return
    fi

    local resolved
    resolved=$(resolve_path "$input")

    # Verify the path exists
    if [[ -n "$resolved" ]]; then
        if ! rclone lsd "b2crypt:${resolved}" &>/dev/null; then
            error "Not a directory: ${input}"
            return 1
        fi
    fi

    CURRENT_PATH="$resolved"
}

cmd_pwd() {
    if [[ -n "$CURRENT_PATH" ]]; then
        echo "/${CURRENT_PATH}"
    else
        echo "/"
    fi
}

cmd_get() {
    local input="$1"

    if [[ "$input" == "." || "$input" == "*" ]]; then
        # Download current directory
        local rc=$(rc_path)
        local dest="${RESTORE_DIR}/${CURRENT_PATH}"
        mkdir -p "$dest"
        info "Downloading ${rc}/ -> ${dest}/"
        rclone copy "$rc" "$dest" --transfers 4 --progress
        info "Download complete: ${dest}/"
        return
    fi

    local resolved
    resolved=$(resolve_path "$input")
    local rc="b2crypt:${resolved}"

    # Check if it's a directory
    if rclone lsd "$rc" &>/dev/null 2>&1; then
        local dest="${RESTORE_DIR}/${resolved}"
        mkdir -p "$dest"
        info "Downloading ${rc}/ -> ${dest}/"
        rclone copy "$rc" "$dest" --transfers 4 --progress
        info "Download complete: ${dest}/"
        return
    fi

    # Check if it's a file (exact match via lsf)
    local dir
    dir=$(dirname "$resolved")
    local base
    base=$(basename "$resolved")
    local parent_rc="b2crypt:${dir}"

    if rclone lsf "$parent_rc" --files-only 2>/dev/null | grep -qxF "$base"; then
        local dest="${RESTORE_DIR}/${resolved}"
        mkdir -p "$(dirname "$dest")"
        info "Downloading ${rc} -> ${dest}"
        rclone copyto "$rc" "$dest" --progress
        info "Download complete."
        return
    fi

    error "Not found: ${input}"
}

cmd_getall() {
    local rc=$(rc_path)
    local dest="${RESTORE_DIR}/${CURRENT_PATH}"
    mkdir -p "$dest"
    info "Downloading ALL from ${rc}/ -> ${dest}/"
    rclone copy "$rc" "$dest" --transfers 4 --progress
    info "Download complete: ${dest}/"
}

cmd_find() {
    local pattern="$1"
    local rc=$(rc_path)

    echo ""
    local results=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && results+=("$line")
    done < <(rclone lsl "$rc" --include "*${pattern}*" 2>/dev/null || true)

    if [[ ${#results[@]} -eq 0 ]]; then
        echo "No matches for '${pattern}'"
        return
    fi

    echo "Found ${#results[@]} match(es) for '${pattern}':"
    echo ""
    local shown=0
    for line in "${results[@]+"${results[@]}"}"; do
        [[ -z "$line" ]] && continue
        ((shown >= 100)) && echo "  ... and $((${#results[@]} - 100)) more" && break
        local size name
        size=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | cut -d' ' -f4-)
        printf "  %8s  %s\n" "$(human_size "$size")" "$name"
        ((shown++))
    done
}

cmd_tree() {
    local target="${1:-}"
    local rc
    if [[ -n "$target" && "$target" != "." ]]; then
        local resolved
        resolved=$(resolve_path "$target")
        rc="b2crypt:${resolved}"
    else
        rc=$(rc_path)
    fi

    echo ""
    rclone tree "$rc" --dirsfirst 2>/dev/null | head -100
    local total
    total=$(rclone tree "$rc" 2>/dev/null | wc -l | tr -d ' ')
    if (( total > 100 )); then
        echo "... ($((total - 100)) more entries)"
    fi
    echo ""
}

cmd_du() {
    local target="${1:-}"
    local rc
    if [[ -n "$target" && "$target" != "." ]]; then
        local resolved
        resolved=$(resolve_path "$target")
        rc="b2crypt:${resolved}"
    else
        rc=$(rc_path)
    fi

    echo ""
    rclone size "$rc" 2>/dev/null
    echo ""
}

cmd_help() {
    cat <<EOF

  NAVIGATE
  ────────
  ls [-l] [path]     List directory contents (fast: names only, -l: with sizes/counts)
  cd <path>         Change directory (.. to go back, / for root)
  pwd               Show current path
  tree [path]       Show directory tree
  du [path]         Show size summary

  DOWNLOAD
  ────────
  get <name>        Download a file or folder by name
  get .             Download everything in current directory
  getall            Same as get .
  download-all      Download EVERYTHING from root
  find <pattern>    Search for files, then get them by path

  OTHER
  ─────
  setdir <path>     Change where files are saved (default: ./restored)
  help              Show this help
  quit              Exit

  Examples:
    cd hamzilla-photos/2024/vacation   # navigate to a folder
    ls                                  # see what's here
    get IMG_001.jpg                    # download one file
    get vacation                        # download a whole folder
    get .                               # download everything here
    download-all                        # download everything in bucket
    find .jpg                           # find all jpgs anywhere

EOF
}

shell() {
    echo ""
    echo "B2 Photo Restore Shell"
    echo "────────────────────────────────────────────"
    echo "Navigate your encrypted backups, download what you need."
    echo ""
    echo "Quick start:"
    echo "  ls            See what's in the bucket"
    echo "  cd <folder>   Navigate into a folder"
    echo "  get <name>    Download a file or folder"
    echo "  get .         Download everything in current dir"
    echo "  download-all  Download everything from root"
    echo "  help          All commands"
    echo ""

    while true; do
        local display_path="${CURRENT_PATH:-/}"
        printf "\033[1;32mb2crypt:\033[1;34m%s\033[0m \$ " "$display_path"
        read -r input

        # Skip empty input
        [[ -z "$input" ]] && continue

        # Parse command and args
        local cmd args
        cmd=$(echo "$input" | awk '{print $1}')
        args=$(echo "$input" | cut -d' ' -f2-)
        [[ "$args" == "$cmd" ]] && args=""

        case "$cmd" in
            ls)
                cmd_ls "$args"
                ;;
            cd)
                if [[ -z "$args" ]]; then
                    error "Usage: cd <path>"
                else
                    cmd_cd "$args"
                fi
                ;;
            pwd)
                cmd_pwd
                ;;
            get)
                if [[ -z "$args" ]]; then
                    error "Usage: get <name|path|.>"
                else
                    cmd_get "$args"
                fi
                ;;
            getall)
                cmd_getall
                ;;
            download-all|downloadall)
                CURRENT_PATH=""
                cmd_getall
                ;;
            find)
                if [[ -z "$args" ]]; then
                    error "Usage: find <pattern>"
                else
                    cmd_find "$args"
                fi
                ;;
            tree)
                cmd_tree "$args"
                ;;
            du)
                cmd_du "$args"
                ;;
            setdir)
                if [[ -z "$args" ]]; then
                    echo "Restore directory: ${RESTORE_DIR}"
                else
                    RESTORE_DIR="$args"
                    info "Restore directory set to: ${RESTORE_DIR}"
                fi
                ;;
            help)
                cmd_help
                ;;
            quit|exit)
                echo "Bye."
                return
                ;;
            *)
                error "Unknown command: ${cmd}. Type 'help' for usage."
                ;;
        esac
    done
}

# --- One-shot commands ---

list_top_level() {
    echo ""
    echo "=== Buckets in b2crypt: ==="
    rclone lsf b2crypt: --dirs-only 2>/dev/null | sed 's|/$||' | while IFS= read -r d; do
        printf "  %s\n" "$d"
    done
    echo ""
}

browse_folder() {
    local folder="$1"
    local saved_path="$CURRENT_PATH"
    CURRENT_PATH="$folder"
    cmd_ls
    CURRENT_PATH="$saved_path"
}

search_files() {
    CURRENT_PATH=""
    cmd_find "$1"
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

Browse & Navigate:
  shell                       Interactive shell (default, no args)
  list                        List top-level folders
  browse <folder>             Show contents of a folder
  search <pattern>            Find files by name

Download:
  download-all                Download everything
  download-folder <folder>    Download a folder
  download-file <path>        Download a single file

Examples:
  $(basename "$0")                              # start interactive shell
  $(basename "$0") list
  $(basename "$0") browse hamzilla-photos
  $(basename "$0") search ".jpg"
  $(basename "$0") download-all
  $(basename "$0") download-folder hamzilla-photos/2024
  $(basename "$0") download-file hamzilla-photos/2024/vacation/photo.jpg
EOF
}

# --- Main ---
check_rclone

if [[ $# -eq 0 ]]; then
    shell
    exit 0
fi

case "${1:-}" in
    shell)          shell ;;
    list)           list_top_level ;;
    browse)         shift; browse_folder "${1:?Usage: $0 browse <folder>}" ;;
    search)         shift; search_files "${1:?Usage: $0 search <pattern>}" ;;
    download-folder) shift; download_folder "${1:?Usage: $0 download-folder <folder>}" ;;
    download-file)  shift; download_file "${1:?Usage: $0 download-file <path>}" ;;
    download-all)   download_all ;;
    -h|--help)      show_usage ;;
    *)              error "Unknown command: $1"; show_usage; exit 1 ;;
esac
