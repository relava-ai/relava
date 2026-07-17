#!/usr/bin/env bash
# Regression test: reconcile_dir() in adapters/claude_code.sh must adopt
# pre-existing real content under ~/.claude/{agents,skills,commands} into the
# kb repo on first sync (the common case: skills/agents installed before
# relava was ever wired in) — but must NOT adopt an item that is itself a git
# repo (e.g. a plugin/marketplace-installed skill collection), since moving
# someone else's repo into the kb repo would only record a dangling gitlink,
# not real content.
#
# Run manually: bash sync/tests/adopt-preexisting.sh
# Uses a throwaway scratch kb/claude dir under mktemp — never touches the
# real ~/.relava/kb or ~/.claude.

set -uo pipefail

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RELAVA_KB_DIR="$WORKDIR/kb"
export RELAVA_CLAUDE_DIR="$WORKDIR/claude"

pass=0
fail=0
check() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  PASS: $desc"
        pass=$((pass + 1))
    else
        echo "  FAIL: $desc"
        fail=$((fail + 1))
    fi
}
content_matches() {
    [ "$(cat "$1" 2>/dev/null)" = "$2" ]
}

echo "--- seed pre-existing real content directly under \$RELAVA_CLAUDE_DIR ---"
mkdir -p "$RELAVA_CLAUDE_DIR/skills/plain-skill" "$RELAVA_CLAUDE_DIR/skills/git-skill" "$RELAVA_CLAUDE_DIR/agents"
echo "# plain" > "$RELAVA_CLAUDE_DIR/skills/plain-skill/SKILL.md"
echo "# git-managed" > "$RELAVA_CLAUDE_DIR/skills/git-skill/SKILL.md"
git init --quiet "$RELAVA_CLAUDE_DIR/skills/git-skill"
echo "# pre-existing agent" > "$RELAVA_CLAUDE_DIR/agents/preexisting.md"

echo "--- bootstrap against a fresh local-only kb (no remote) ---"
mkdir -p "$RELAVA_KB_DIR"
git init --quiet "$RELAVA_KB_DIR"
bash "$SYNC_DIR/sync.sh" full > /dev/null

check "plain skill adopted into kb repo" test -d "$RELAVA_KB_DIR/skills/plain-skill"
check "plain skill symlinked back" test -L "$RELAVA_CLAUDE_DIR/skills/plain-skill"
check "plain skill content preserved through adoption" \
    content_matches "$RELAVA_CLAUDE_DIR/skills/plain-skill/SKILL.md" "# plain"
check "pre-existing agent adopted into kb repo" test -f "$RELAVA_KB_DIR/agents/preexisting.md"
check "pre-existing agent symlinked back" test -L "$RELAVA_CLAUDE_DIR/agents/preexisting.md"

check "git-managed skill NOT adopted (still real dir, not a symlink)" \
    bash -c '[ -d "$1" ] && [ ! -L "$1" ]' _ "$RELAVA_CLAUDE_DIR/skills/git-skill"
check "git-managed skill NOT copied into kb repo" \
    bash -c '[ ! -e "$1" ]' _ "$RELAVA_KB_DIR/skills/git-skill"

echo "--- re-run sync: adoption must be idempotent (no errors, no duplication) ---"
bash "$SYNC_DIR/sync.sh" full > /dev/null
check "plain skill still a single symlink after re-sync" test -L "$RELAVA_CLAUDE_DIR/skills/plain-skill"
check "git-managed skill still left alone after re-sync" \
    bash -c '[ -d "$1" ] && [ ! -L "$1" ]' _ "$RELAVA_CLAUDE_DIR/skills/git-skill"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
