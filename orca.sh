#!/bin/bash
# Managed by zsh-setup

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

find_real_orca() {
    local path_entry
    local resolved_dir
    local candidate
    local IFS=:

    for path_entry in $PATH; do
        [ -n "$path_entry" ] || path_entry=.
        resolved_dir="$(cd "$path_entry" 2>/dev/null && pwd -P)" || continue
        [ "$resolved_dir" = "$SCRIPT_DIR" ] && continue

        candidate="$resolved_dir/orca"
        if [ -x "$candidate" ] && [ ! -d "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

ORCA_BIN="$(find_real_orca)" || {
    printf '%s\n' 'Error: Orca CLI not found in PATH outside the wrapper directory' >&2
    exit 127
}

if [ "$#" -eq 1 ]; then
    case "$1" in
        .|..|/*|./*|../*)
            if [ ! -d "$1" ]; then
                printf 'Error: Orca repository path is not a directory: %s\n' "$1" >&2
                exit 2
            fi

            TARGET_DIR="$(cd "$1" && pwd -P)" || exit 1
            exec "$ORCA_BIN" repo add --path "$TARGET_DIR" --json
            ;;
    esac
fi

exec "$ORCA_BIN" "$@"
