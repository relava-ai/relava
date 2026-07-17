#!/usr/bin/env bash
# Sourceable library — not executable on its own. Defines is_denylisted(),
# shared by sync.sh and every adapter so the pattern list is checked
# identically everywhere rather than reimplemented per caller.
#
# Usage:
#   source ".../denylist-check.sh"
#   is_denylisted "/path/to/file" && echo "blocked"
#
# RELAVA_DENYLIST_FILE overrides which pattern file is used (testing); real
# usage relies on the default, co-located sync/denylist.txt.

RELAVA_DENYLIST_FILE="${RELAVA_DENYLIST_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/denylist.txt}"

# Returns 0 (true) if $1 matches any pattern in the denylist, checked against
# both the full path and the basename — so path-shaped patterns
# ("transcripts/*") and filename-shaped patterns ("CLAUDE.local.md") both work
# without the caller needing to know which kind it is. Uses POSIX `case`
# globbing, not external tools — portable to any shell, not just bash.
is_denylisted() {
    local path="$1"
    local base
    base="$(basename "$path")"
    [ -f "$RELAVA_DENYLIST_FILE" ] || return 1

    local pattern
    while IFS= read -r pattern || [ -n "$pattern" ]; do
        [ -z "$pattern" ] && continue
        case "$pattern" in \#*) continue ;; esac
        case "$path" in $pattern) return 0 ;; esac
        case "$base" in $pattern) return 0 ;; esac
    done < "$RELAVA_DENYLIST_FILE"

    return 1
}
