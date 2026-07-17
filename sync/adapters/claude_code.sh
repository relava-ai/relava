#!/usr/bin/env bash
# Claude Code adapter — reconciles ~/.claude/{agents,skills,commands} with the
# personal kb repo, and keeps ~/.claude/CLAUDE.md's wiki pointer in sync.
# Standalone executable, invoked by sync.sh's run_adapters() with a phase
# argument ("pull" or "push"), or runnable directly for testing.
#
# Hardcodes its own source paths — no manifest (see EXECUTION_PLAN.md §2a).
#
# Auto-memory: current project only, never all projects — a user's machine
# commonly has many unrelated projects (some employer-confidential), and
# auto-memory is per-project content that can hold specifics from any of
# them. Scoping to $CLAUDE_PROJECT_DIR (set by Claude Code on every hook
# invocation) means a sync only ever touches the memory for whatever project
# is actually active, never reaches into any other project's folder.

set -uo pipefail

PHASE="${1:-push}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../denylist-check.sh
source "$SYNC_DIR/denylist-check.sh"

CLAUDE_DIR="${RELAVA_CLAUDE_DIR:-$HOME/.claude}"
REPO="${RELAVA_KB_DIR:-$HOME/.relava/kb}"

is_windows() {
    case "$(uname -s 2>/dev/null || echo unknown)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
    esac
    [ -n "${OS:-}" ] && [ "$OS" = "Windows_NT" ]
}

# Reconcile one category (agents/skills/commands) between $REPO/$1 and
# $CLAUDE_DIR/$1. Direction-agnostic on macOS/Linux (a symlink has no
# direction); phase-aware on Windows (copy needs to know which way).
reconcile_dir() {
    local name="$1"
    local src="$REPO/$name"
    local dst="$CLAUDE_DIR/$name"
    mkdir -p "$src" "$dst"

    if is_windows; then
        if [ "$PHASE" = "pull" ]; then
            # New/changed content from git -> live Claude Code paths.
            copy_tree "$src" "$dst"
        else
            # Local edits made directly in ~/.claude -> repo, so git can see them.
            copy_tree "$dst" "$src"
        fi
        return 0
    fi

    # macOS/Linux: real symlinks, safe to reconcile every phase.
    local item name_only link

    # Adopt any real (non-symlink) content that already lives directly under
    # $dst but has no counterpart in $src yet — the common case of installing
    # skills/agents/commands before relava was ever wired in. The repo is
    # already canonical for every other item this function manages; make it
    # canonical here too by moving the content in, then let the loop below
    # symlink it straight back like any other repo-sourced item.
    for item in "$dst"/*; do
        [ -e "$item" ] || continue
        [ -L "$item" ] && continue
        name_only="$(basename "$item")"
        if [ -e "$item/.git" ]; then
            # A nested git repo (e.g. a plugin/marketplace-installed skill
            # collection) has its own identity and history — adopting it would
            # bury someone else's repo as a plain subtree inside the personal
            # kb repo (git records it as a dangling gitlink, not real content,
            # so the data wouldn't even round-trip through a clone). Leave it
            # local-only and unmanaged, like an unresolved-conflict item.
            echo "relava sync: $item is its own git repo — leaving it unmanaged by relava (not adopting)" >&2
            continue
        fi
        if [ -e "$src/$name_only" ]; then
            echo "relava sync: $item and $src/$name_only both exist — leaving $item alone (resolve manually)" >&2
            continue
        fi
        mv "$item" "$src/$name_only"
        echo "relava sync: adopted pre-existing $item into $src/" >&2
    done

    for item in "$src"/*; do
        [ -e "$item" ] || continue
        name_only="$(basename "$item")"
        link="$dst/$name_only"
        if [ -L "$link" ]; then
            [ "$(readlink "$link")" = "$item" ] || ln -sf "$item" "$link"
        elif [ -e "$link" ]; then
            echo "relava sync: $link already exists and isn't a Relava-managed symlink — skipping (resolve manually)" >&2
        else
            ln -s "$item" "$link"
        fi
    done

    # Remove dangling symlinks for items that no longer exist in the repo.
    for link in "$dst"/*; do
        [ -L "$link" ] || continue
        [ -e "$link" ] && continue
        rm -f "$link"
    done
}

# Overwrite-copy every item from $1 into $2 (Windows path only). Denylist is
# not applied here — agents/skills/commands don't contain sensitive/local-only
# content by convention (EXECUTION_PLAN.md §2a); denylist filtering matters for
# auto-memory specifically, handled separately.
#
# KNOWN LIMITATION (v1, Windows only): this does not mirror deletions — if an
# item is removed from the repo, the stale copy in $to is not cleaned up. The
# symlink path (macOS/Linux) does this correctly via dangling-link detection,
# but a plain copy is indistinguishable from an unrelated file a user created
# by hand, so safe deletion-reconciliation needs extra state (e.g. a manifest
# of what was last copied) to tell those apart. Not implemented here — this
# environment can't execute/test the Windows path at all, and that state
# mechanism deserves real testing before it exists, not a blind guess.
copy_tree() {
    local from="$1" to="$2"
    local item name_only
    for item in "$from"/*; do
        [ -e "$item" ] || continue
        name_only="$(basename "$item")"
        rm -rf "${to:?}/${name_only}"
        cp -Rf "$item" "$to/$name_only"
    done
}

# Idempotent @import line — only added once the target actually exists
# (the personal wiki index, bootstrapped in a later task, P1.W2.1). Adding an
# import for a file that doesn't exist yet would be a dangling reference;
# this just quietly does nothing until the prerequisite lands, and activates
# automatically on a later sync once it does.
ensure_claude_md_import() {
    local wiki_index="$REPO/wiki/index.md"
    [ -f "$wiki_index" ] || return 0

    local claude_md="$CLAUDE_DIR/CLAUDE.md"
    local import_line="@$wiki_index"
    mkdir -p "$CLAUDE_DIR"
    touch "$claude_md"
    grep -qxF "$import_line" "$claude_md" || printf '%s\n' "$import_line" >> "$claude_md"
}

# Auto-memory: one direction only (local -> repo), push phase only. Never
# synced back out on pull — that's Claude Code's own live working memory for
# whatever project is active, not something a stale git pull should ever
# overwrite. $CLAUDE_PROJECT_DIR is documented (set on every hook invocation);
# the memory/ layout under ~/.claude/projects/<slug>/ is NOT documented
# (inferred from observed behavior on this machine) — degrade gracefully (no-op)
# if anything's missing, never guess at an undocumented structure.
sync_memory() {
    [ "$PHASE" = "push" ] || return 0
    [ -n "${CLAUDE_PROJECT_DIR:-}" ] || return 0

    # Slug: non-alphanumeric characters -> '-', per Claude Code's project-slug
    # convention (confirmed empirically against this machine's own
    # ~/.claude/projects/ layout, not a stable documented API).
    local slug
    slug="$(printf '%s' "$CLAUDE_PROJECT_DIR" | sed 's/[^a-zA-Z0-9]/-/g')"

    local mem_src="$CLAUDE_DIR/projects/$slug/memory"
    [ -d "$mem_src" ] || return 0

    local mem_dst="$REPO/memory/$slug"
    mkdir -p "$mem_dst"

    local item name_only
    for item in "$mem_src"/*; do
        [ -e "$item" ] || continue
        name_only="$(basename "$item")"
        is_denylisted "$item" && continue
        cp -Rf "$item" "$mem_dst/$name_only"
    done

    # Mirror deletions: $mem_dst is entirely Relava-managed (unlike the
    # agents/skills case, there's no legitimate reason for a user to hand-place
    # files here), so it's safe to remove anything no longer in the source.
    # ${mem_dst:?}/${name_only:?} guard against either ever being empty before
    # an rm -rf — mem_dst is always non-empty in practice ($REPO always has a
    # fallback default), but this fails loudly instead of silently expanding
    # to a dangerous path if that ever stops being true.
    for item in "$mem_dst"/*; do
        [ -e "$item" ] || continue
        name_only="$(basename "$item")"
        [ -e "$mem_src/$name_only" ] || rm -rf "${mem_dst:?}/${name_only:?}"
    done
}

reconcile_dir "agents"
reconcile_dir "skills"
reconcile_dir "commands"
ensure_claude_md_import
sync_memory

exit 0
