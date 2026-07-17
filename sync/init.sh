#!/usr/bin/env bash
# One-time, friendlier entry point than bootstrap.sh directly: detects git/gh
# availability and auth, offers to auto-create the personal kb repo via
# `gh repo create`, then hands off to bootstrap.sh. Matches the onboarding UX
# in EXECUTION_PLAN.md §0a ("first run detects git/gh auth, offers to
# auto-create the personal repo, defaults everything else").
#
# Run once: bash sync/init.sh
#
# Auth is never handled here — if gh isn't authenticated, this prints
# instructions and exits, leaving the actual login flow to the user (same
# precedent as everywhere else in this project).

set -uo pipefail

SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${RELAVA_KB_DIR:-$HOME/.relava/kb}"
REPO_NAME="${RELAVA_KB_REPO_NAME:-kb-$(whoami)}"

# 1. Tool availability.
command -v git > /dev/null 2>&1 || {
    echo "relava init: git is required, not found in PATH" >&2
    exit 1
}
command -v gh > /dev/null 2>&1 || {
    echo "relava init: gh (GitHub CLI) not found — needed to auto-create the personal repo." >&2
    echo "  Install: https://cli.github.com/, then re-run this script." >&2
    echo "  Or skip auto-create entirely: bash $SYNC_DIR/bootstrap.sh (creates a local-only repo)." >&2
    exit 1
}

# 2. Already set up? Don't re-prompt or re-create.
if [ -d "$REPO/.git" ] && git -C "$REPO" remote get-url origin > /dev/null 2>&1; then
    echo "relava init: $REPO already exists with a remote configured — nothing to do."
    echo "  (to re-run hook wiring anyway: bash $SYNC_DIR/bootstrap.sh)"
    exit 0
fi

# 3. gh auth check — detected and reported, never handled here.
if ! GH_STATUS="$(gh auth status 2>&1)"; then
    echo "relava init: gh is not authenticated." >&2
    echo "  Run: gh auth login" >&2
    echo "  Then re-run this script." >&2
    exit 1
fi

# 3b. Multiple gh accounts logged in (e.g. personal + work)? gh operates
#     against whichever one is "active" with no other signal — silently
#     creating the kb repo under the wrong account is a real, easy-to-hit
#     mistake (this project's own maintainers hit exactly this). Confirm
#     explicitly before creating anything, rather than assuming.
ACCOUNT_COUNT="$(printf '%s\n' "$GH_STATUS" | grep -c "Logged in to github.com")"
if [ "$ACCOUNT_COUNT" -gt 1 ]; then
    ACTIVE_ACCOUNT="$(printf '%s\n' "$GH_STATUS" | grep -B1 "Active account: true" | grep "Logged in to" | sed -E 's/.*account ([^ ]+).*/\1/')"
    echo "relava init: multiple gh accounts are logged in — active account is '$ACTIVE_ACCOUNT'." >&2
    echo "  If this isn't the account that should own your personal kb repo, run:" >&2
    echo "    gh auth switch --hostname github.com --user <account>" >&2
    echo "  then re-run this script." >&2
    read -r -p "  Continue creating the repo under '$ACTIVE_ACCOUNT'? [y/N] " reply
    case "$reply" in
        [yY]*) ;;
        *)
            echo "  Aborting — switch accounts and re-run." >&2
            exit 1
            ;;
    esac
fi

# 4. Offer to auto-create the personal repo (skip if the local repo already
#    exists but just happens to have no remote yet — bootstrap.sh's existing
#    local-only path handles that case, nothing to create here).
REMOTE_URL=""
if [ ! -d "$REPO/.git" ]; then
    read -r -p "relava init: create a private GitHub repo '$REPO_NAME' for your personal kb? [Y/n] " reply
    case "$reply" in
        [nN]*)
            echo "  Skipping auto-create — bootstrap.sh will set up a local-only repo instead."
            ;;
        *)
            if gh repo view "$REPO_NAME" > /dev/null 2>&1; then
                echo "  = $REPO_NAME already exists on GitHub, using it"
            else
                gh repo create "$REPO_NAME" --private \
                    --description "Personal Relava knowledge-base repo (agents/skills/wiki/memory)" \
                    > /dev/null
                echo "  + created $REPO_NAME"
            fi
            REMOTE_URL="$(gh repo view "$REPO_NAME" --json sshUrl --jq .sshUrl)"
            ;;
    esac
fi

# 5. Hand off to bootstrap.sh — empty REMOTE_URL falls through to its
#    existing local-only path, exactly as if no argument were given.
bash "$SYNC_DIR/bootstrap.sh" "$REMOTE_URL"
