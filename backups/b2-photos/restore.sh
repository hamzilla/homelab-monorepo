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

human_size() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        printf "%.1f GB" "$(echo "$bytes / 1073741824" | bc -l)"
    elif (( bytes >= 1048576 )); then
        printf "%.1f MB" "$(echo "$bytes / 1048576" | bc -l)"
    elif (( bytes >= 1024 )); then
        printf "%.1f KB" "$(echo "$bytes / 1024" | bc -l)"
    else
        printf "%d B" "$bytes"
    fi
}

list_top_level() {
    echo ""
    echo "=== Buckets in b2crypt: ==="
    rclone lsd b2crypt: 2>/dev/null | awk '{print "  " $NF}'
    echo ""
}

browse_folder() {
    local folder="$1"
    local path="${folder}"
    [[ "$path" == */ ]] && path="${path%/}"

    echo ""
    echo "=== b2crypt:${path}/ ==="
    echo ""

    # Get subdirectories
    local dirs
    dirs=$(rclone lsd "b2crypt:${path}" 2>/dev/null | awk '{print $NF}' || true)

    # Get files with sizes
    local files
    files=$(rclone lsl "b2crypt:${path}" --max-depth 1 2>/dev/null | grep -v '/$' || true)

    if [[ -n "$dirs" ]]; then
        echo "  FOLDERS:"
        while IFS= read -r d; do
            [[ -z "$d" ]] && continue
            local count
            count=$(rclone ls "b2crypt:${path}/${d}" 2>/dev/null | wc -l | tr -d ' ')
            echo "    ${d}/  (${count} items)"
        done <<< "$dirs"
        echo ""
    fi

    if [[ -n "$files" ]]; then
        echo "  FILES:"
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local size name
            size=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":""); print ""}')
            echo "    $(human_size "$size")  ${name}"
        done <<< "$files" | head -50
        local file_count
        file_count=$(echo "$files" | wc -l | tr -d ' ')
        if (( file_count > 50 )); then
            echo "    ... and $((file_count - 50)) more files"
        fi
        echo ""
    fi

    if [[ -z "$dirs" && -z "$files" ]]; then
        echo "  (empty)"
        echo ""
    fi
}

browse_interactive() {
    local current="${1:-}"
    while true; do
        local display_path="${current:-<root>}"
        echo ""
        echo "=== b2crypt:${current:+${current}/} ==="
        echo ""

        # Get subdirectories
        local dirs=()
        if [[ -n "$current" ]]; then
            while IFS= read -r d; do
                [[ -n "$d" ]] && dirs+=("$d")
            done < <(rclone lsd "b2crypt:${current}" 2>/dev/null | awk '{print $NF}')
        else
            while IFS= read -r d; do
                [[ -n "$d" ]] && dirs+=("$d")
            done < <(rclone lsd b2crypt: 2>/dev/null | awk '{print $NF}')
        fi

        # Get files
        local files=()
        local cmd="rclone lsl b2crypt:${current} --max-depth 1 2>/dev/null"
        while IFS= read -r line; do
            [[ -n "$line" ]] && files+=("$line")
        done < <(eval "$cmd" | grep -v '/$' || true)

        # Display directories
        local idx=1
        if [[ ${#dirs[@]} -gt 0 ]]; then
            echo "  FOLDERS:"
            for d in "${dirs[@]}"; do
                local count
                count=$(rclone ls "b2crypt:${current:+${current}/}${d}" 2>/dev/null | wc -l | tr -d ' ')
                printf "    %2d) %s/  (%s items)\n" "$idx" "$d" "$count"
                ((idx++))
            done
            echo ""
        fi

        # Display files
        if [[ ${#files[@]} -gt 0 ]]; then
            echo "  FILES:"
            local shown=0
            for line in "${files[@]}"; do
                ((shown >= 50)) && break
                local size name
                size=$(echo "$line" | awk '{print $1}')
                name=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":""); print ""}')
                printf "    %2d) %s  %s\n" "$idx" "$(human_size "$size")" "$name"
                ((idx++))
                ((shown++))
            done
            if [[ ${#files[@]} -gt 50 ]]; then
                echo "    ... and $((${#files[@]} - 50)) more files"
            fi
            echo ""
        fi

        if [[ ${#dirs[@]} -eq 0 && ${#files[@]} -eq 0 ]]; then
            echo "  (empty)"
            echo ""
        fi

        # Navigation prompt
        echo "  Commands: [number] open folder, [d <num>] download file, [b] back, [q] quit"
        echo ""
        read -rp "  > " input

        case "$input" in
            b|B)
                if [[ -n "$current" ]]; then
                    current="${current%/*}"
                else
                    return
                fi
                ;;
            q|Q)
                return
                ;;
            d)
                read -rp "  File number: " fnum
                local file_idx=$((fnum - ${#dirs[@]}))
                if (( file_idx >= 1 && file_idx <= ${#files[@]} )); then
                    local fname
                    fname=$(echo "${files[$((file_idx-1))]}" | awk '{for(i=5;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":""); print ""}')
                    local fpath="${current:+${current}/}${fname}"
                    download_file "$fpath"
                else
                    error "Invalid file number."
                fi
                ;;
            [0-9]*)
                if (( input >= 1 && input <= ${#dirs[@]} )); then
                    local selected="${dirs[$((input-1))]}"
                    current="${current:+${current}/}${selected}"
                elif (( input > ${#dirs[@]} && input < idx )); then
                    local file_idx=$((input - ${#dirs[@]}))
                    local fname
                    fname=$(echo "${files[$((file_idx-1))]}" | awk '{for(i=5;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":""); print ""}')
                    local fpath="${current:+${current}/}${fname}"
                    download_file "$fpath"
                else
                    error "Invalid selection."
                fi
                ;;
            *)
                error "Invalid input."
                ;;
        esac
    done
}

search_files() {
    local pattern="$1"
    echo ""
    echo "=== Searching for '${pattern}' ==="
    echo ""

    local results=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && results+=("$line")
    done < <(rclone lsl b2crypt: --include "*${pattern}*" 2>/dev/null || true)

    if [[ ${#results[@]} -eq 0 ]]; then
        echo "  No matches found."
        echo ""
        return
    fi

    echo "  Found ${#results[@]} match(es):"
    echo ""
    local shown=0
    for line in "${results[@]}"; do
        ((shown >= 50)) && break
        local size name
        size=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":""); print ""}')
        printf "    %s  %s\n" "$(human_size "$size")" "$name"
        ((shown++))
    done
    if [[ ${#results[@]} -gt 50 ]]; then
        echo "  ... and $((${#results[@]} - 50)) more matches"
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
  list                          List top-level folders in the bucket
  browse <folder>               Browse a folder (one-shot)
  browse -i                     Interactive folder browser (navigate with numbers)
  search <pattern>              Search for files by name
  download-folder <folder>      Download an entire folder
  download-file <path>          Download a single file
  download-all                  Download everything
  interactive                   Interactive menu (default)

Examples:
  $(basename "$0") list
  $(basename "$0") browse hamzilla-photos
  $(basename "$0") browse -i
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
        echo "║  2) Browse (one-shot)            ║"
        echo "║  3) Browse (interactive)         ║"
        echo "║  4) Search for files             ║"
        echo "║  5) Download a folder            ║"
        echo "║  6) Download a file              ║"
        echo "║  7) Download everything          ║"
        echo "║  8) Change restore directory     ║"
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
                read -rp "Start folder (empty for root): " folder
                browse_interactive "$folder"
                ;;
            4)
                read -rp "Search pattern: " pattern
                search_files "$pattern"
                ;;
            5)
                read -rp "Folder to download: " folder
                download_folder "$folder"
                ;;
            6)
                read -rp "File path (e.g. hamzilla-photos/2024/photo.jpg): " filepath
                download_file "$filepath"
                ;;
            7)
                read -rp "Download ALL files? This may take a while. [y/N] " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] && download_all
                ;;
            8)
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
    browse)
        shift
        if [[ "${1:-}" == "-i" ]]; then
            browse_interactive ""
        else
            browse_folder "${1:?Usage: $0 browse <folder> | $0 browse -i}"
        fi
        ;;
    search)         shift; search_files "${1:?Usage: $0 search <pattern>}" ;;
    download-folder) shift; download_folder "${1:?Usage: $0 download-folder <folder>}" ;;
    download-file)  shift; download_file "${1:?Usage: $0 download-file <path>}" ;;
    download-all)   download_all ;;
    interactive)    interactive_menu ;;
    -h|--help)      show_usage ;;
    *)              error "Unknown command: $1"; show_usage; exit 1 ;;
esac
