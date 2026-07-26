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
    local target="${1:-}"
    local rc
    if [[ -n "$target" && "$target" != "." ]]; then
        local resolved
        resolved=$(resolve_path "$target")
        rc="b2crypt:${resolved}"
    else
        rc=$(rc_path)
    fi

    # Get directories
    local dirs=()
    while IFS= read -r d; do
        [[ -n "$d" ]] && dirs+=("$d")
    done < <(rclone lsd "$rc" 2>/dev/null | awk '{print $NF}')

    # Get files with sizes
    local files=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && files+=("$line")
    done < <(rclone lsl "$rc" --max-depth 1 2>/dev/null | grep -v '/$' || true)

    if [[ ${#dirs[@]} -eq 0 && ${#files[@]} -eq 0 ]]; then
        echo "(empty)"
        return
    fi

    # Print directories
    for d in "${dirs[@]}"; do
        local count
        count=$(rclone ls "${rc}/${d}" 2>/dev/null | wc -l | tr -d ' ')
        printf "  \033[1;34m%-40s\033[0m  %s items\n" "${d}/" "$count"
    done

    # Print files
    for line in "${files[@]}"; do
        local size name
        size=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":""); print ""}')
        printf "  %-40s  %s\n" "$name" "$(human_size "$size")"
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

    if [[ "$input" == "." ]]; then
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

    # Check if it's a file
    local dir
    dir=$(dirname "$resolved")
    local base
    base=$(basename "$resolved")
    local parent_rc="b2crypt:${dir}"

    if rclone lsl "$parent_rc" --max-depth 1 2>/dev/null | grep -q "$base"; then
        local dest="${RESTORE_DIR}/${resolved}"
        mkdir -p "$(dirname "$dest")"
        info "Downloading ${rc} -> ${dest}"
        rclone copyto "$rc" "$dest" --progress
        info "Download complete."
        return
    fi

    error "Not found: ${input}"
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
    for line in "${results[@]}"; do
        ((shown >= 100)) && echo "  ... and $((${#results[@]} - 100)) more" && break
        local size name
        size=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":""); print ""}')
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

Commands:
  ls [path]         List directory contents (default: current)
  cd <path>         Change directory (supports .. and /)
  pwd               Print current directory
  get <name>        Download a file or folder (use "." for current dir)
  find <pattern>    Search for files by name pattern
  tree [path]       Show directory tree
  du [path]         Show size summary
  setdir <path>     Change local restore directory
  help              Show this help
  quit / exit       Exit the shell

Path shortcuts:
  ..                Parent directory
  /                 Root directory
  ~                 Root directory
  .                 Current directory

Examples:
  ls
  cd hamzilla-photos
  cd 2024/vacation
  cd ..
  get vacation-photos
  get photo.jpg
  get .               (download everything in current dir)
  find .jpg
  tree
  du

EOF
}

shell() {
    echo ""
    echo "B2 Photo Restore Shell"
    echo "Type 'help' for commands, 'quit' to exit"
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
    rclone lsd b2crypt: 2>/dev/null | awk '{print "  " $NF}'
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

Commands:
  shell                       Interactive filesystem shell (default)
  list                        List top-level folders
  browse <folder>             Browse a folder (one-shot)
  search <pattern>            Search for files by name
  download-folder <folder>    Download an entire folder
  download-file <path>        Download a single file
  download-all                Download everything

Examples:
  $(basename "$0")                          # start interactive shell
  $(basename "$0") list
  $(basename "$0") browse hamzilla-photos
  $(basename "$0") search ".jpg"
  $(basename "$0") download-folder hamzilla-photos/2024
  $(basename "$0") download-file hamzilla-photos/2024/photo.jpg
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
