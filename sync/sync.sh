#!/usr/bin/env bash
# Sync the personal Relava knowledge-base repo (~/.relava/kb) across machines.
# Invoked by Claude Code hooks: non-interactive, never blocks, always exits 0.
#
# Modes:
#   sync.sh          full : pull, then push local work if any   (SessionStart)
#   sync.sh pull     pull only                                   (UserPromptSubmit — start of turn)
#   sync.sh push     push local work if any, else do NOTHING     (Stop — end of turn)
#                    push makes NO network call when the tree is clean and nothing is unpushed.
#
# RELAVA_KB_DIR overrides the repo path (testing against a scratch repo); real
# usage relies on the default.
#
# Adapted from chris_second_brain/sync.sh.

set -uo pipefail

REPO="${RELAVA_KB_DIR:-$HOME/.relava/kb}"
MODE="${1:-full}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./denylist-check.sh
source "$SCRIPT_DIR/denylist-check.sh"

cd "$REPO" 2>/dev/null || exit 0

# Skip if this isn't a git repo yet (e.g. clone not finished).
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Keep sync plumbing out of the tracked tree — local-only via .git/info/exclude,
# never a committed .gitignore, since these are machine-specific and irrelevant
# to the synced knowledge content itself.
EXCLUDE_FILE="$(git rev-parse --git-dir)/info/exclude"
for pattern in ".sync.log" ".sync.lock.d"; do
    grep -qxF "$pattern" "$EXCLUDE_FILE" 2>/dev/null || echo "$pattern" >> "$EXCLUDE_FILE"
done

# Heartbeat so hook firing is observable: tail -f ~/.relava/kb/.sync.log
# Timestamp uses a portable +FORMAT (not -Iseconds, a GNU/newer-BSD extension
# not guaranteed on every platform); hostname has no -s (short-name flag support
# on Windows' bundled hostname is unconfirmed, and the full name is fine here).
echo "$(date +"%Y-%m-%dT%H:%M:%S%z") sync ($MODE) on $(hostname)" >> "$REPO/.sync.log"

# Serialize concurrent runs on the same machine (hook overlap). mkdir is atomic
# and portable (unlike flock, which isn't available on macOS by default).
LOCK_DIR="$REPO/.sync.lock.d"
mkdir "$LOCK_DIR" 2>/dev/null || exit 0
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

run_adapters() {
    # Each adapter is a standalone executable, called with a phase argument
    # ("pull" or "push"). Symlink-based adapters can ignore phase (a symlink has
    # no direction — editing either path edits the same file), but copy-based
    # platforms (Windows) need it: pull reconciles repo -> ~/.claude (new/changed
    # content in), push captures ~/.claude -> repo (local edits out). Adapters
    # check is_denylisted() (sourced above) before reading any source file.
    local phase="$1"
    local adapters_dir="$SCRIPT_DIR/adapters"
    [ -d "$adapters_dir" ] || return 0
    for adapter in "$adapters_dir"/*.sh; do
        [ -e "$adapter" ] || continue
        [ -x "$adapter" ] || continue
        "$adapter" "$phase" || echo "relava sync: adapter $(basename "$adapter") ($phase) failed — continuing" >&2
    done
}

pull_now() {
    # No upstream configured yet (e.g. a fresh local-only repo before a remote
    # exists) is expected and not an error — skip the pull attempt silently
    # rather than surfacing git's "no tracking information" message, but still
    # reconcile local state via adapters.
    if git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
        # --autostash tucks away uncommitted edits so the rebase applies, then restores them.
        git pull --rebase --autostash --quiet || {
            echo "relava sync: pull failed (conflict or offline) — resolve manually in $REPO" >&2
            return 1
        }
    fi
    run_adapters pull
}

push_if_changes() {
    run_adapters push

    # Every check here is LOCAL — no network unless there is genuinely something to send.
    git add -A

    # Safety net: each adapter is responsible for checking is_denylisted() before
    # ever reading a source file (denylist-before-read), so nothing denylisted
    # should reach this point — but this is the last line of defense before
    # anything gets committed, not the primary enforcement. Unstage rather than
    # delete: never destroy local data, just refuse to let it enter git history.
    local blocked=0 f
    while IFS= read -r -d '' f; do
        if is_denylisted "$f"; then
            echo "relava sync: REFUSING to commit denylisted file: $f (unstaged, left in working tree)" >&2
            git reset --quiet -- "$f"
            blocked=1
        fi
    done < <(git diff --cached --name-only -z)
    [ "$blocked" = 0 ] || echo "relava sync: denylisted file(s) blocked from this sync — check the adapter that wrote them" >&2

    if ! git diff --cached --quiet; then
        # A genuinely fresh machine (git installed, never configured) has no
        # user.name/user.email anywhere — git's own commit failure message
        # ("Author identity unknown... fatal: empty ident name") is accurate
        # but unfriendly for a tool that's supposed to run silently from a
        # hook. Check first and give a clear, actionable message instead;
        # never fabricate an identity on the user's behalf. Changes stay
        # staged (nothing lost) — the next sync commits them once identity
        # is configured. Matches this script's own "never blocks, always
        # exits 0" contract (see header).
        if git config user.name > /dev/null 2>&1 && git config user.email > /dev/null 2>&1; then
            git commit --quiet -m "sync from $(hostname) $(date +"%Y-%m-%dT%H:%M:%S%z")"
        else
            echo "relava sync: no git identity configured — changes staged but not committed." >&2
            echo "  Run: git config --global user.name \"Your Name\" && git config --global user.email \"you@example.com\"" >&2
            echo "  Then re-sync (automatic on the next turn, or: bash $SCRIPT_DIR/sync.sh push)" >&2
        fi
    fi

    # No remote configured at all -> local-only repo, nothing to push to.
    git remote get-url origin > /dev/null 2>&1 || return 0

    if git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' > /dev/null 2>&1; then
        # Normal case: upstream tracking exists, so unpushed-commit count is a
        # cheap local check — no network call unless there's genuinely
        # something to send. @{upstream} is git's own ref syntax (the
        # configured upstream tracking branch), passed through literally as
        # a git argument — not shell brace expansion.
        # shellcheck disable=SC1083
        [ "$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo 0)" != 0 ] || return 0
        git push --quiet || {
            # Remote advanced during the turn: reconcile, then retry once.
            git pull --rebase --autostash --quiet && git push --quiet \
                || echo "relava sync: push failed (offline or conflict) — will retry next run" >&2
        }
    else
        # A remote is configured but no upstream tracking exists yet — e.g.
        # this repo was cloned from a remote that was still empty at the time
        # (a brand-new bootstrap), so git never had a branch to track. Only
        # push if there's actually a commit to send (HEAD must resolve — an
        # unborn branch with nothing committed yet has nothing to push).
        git rev-parse HEAD > /dev/null 2>&1 || return 0
        git push --quiet -u origin HEAD || {
            git pull --rebase --autostash --quiet && git push --quiet -u origin HEAD \
                || echo "relava sync: initial push failed (offline or conflict) — will retry next run" >&2
        }
    fi
}

case "$MODE" in
    pull) pull_now ;;
    push) push_if_changes ;;
    full) pull_now && push_if_changes ;;
    *)    echo "relava sync: unknown mode '$MODE'" >&2 ;;
esac

exit 0
