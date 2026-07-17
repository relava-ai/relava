#!/usr/bin/env bash
# Nuke-and-restore test (P1.W1.5): deleting the personal kb repo and the
# ~/.claude state entirely, then re-running bootstrap.sh, should fully restore
# local state from the remote — symlinks re-created, CLAUDE.md import line
# re-added, content matching exactly. Nothing should be lost.
#
# Run manually: bash sync/tests/nuke-and-restore.sh
# Uses a throwaway scratch remote/kb/claude dir under mktemp — never touches
# the real ~/.relava/kb or ~/.claude.

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

echo "--- seed a remote with content ---"
git init --bare --quiet "$WORKDIR/remote.git"
git clone --quiet "$WORKDIR/remote.git" "$WORKDIR/seed"
# Force the branch name explicitly rather than relying on git's own
# init.defaultBranch — that's ambient machine config (varies: some
# platforms/installs default to "master", not "main") and this test must
# not depend on it to be portable.
git -C "$WORKDIR/seed" checkout -b main --quiet
git -C "$WORKDIR/seed" config user.email "test@relava.local"
git -C "$WORKDIR/seed" config user.name "Relava Test"
mkdir -p "$WORKDIR/seed/agents"
echo "# seeded agent" > "$WORKDIR/seed/agents/seeded.md"
git -C "$WORKDIR/seed" add -A
git -C "$WORKDIR/seed" commit --quiet -m seed
git -C "$WORKDIR/seed" push --quiet -u origin main

echo "--- first bootstrap ---"
bash "$SYNC_DIR/bootstrap.sh" "$WORKDIR/remote.git" > /dev/null

check "kb repo exists after first bootstrap" test -d "$RELAVA_KB_DIR/.git"
check "seeded agent symlinked" test -L "$RELAVA_CLAUDE_DIR/agents/seeded.md"

# Give the CLAUDE.md import line something to point at, then re-sync so it
# actually gets added — proves the nuke-and-restore also restores state that
# only exists because of a *previous* sync, not just the initial clone.
mkdir -p "$RELAVA_KB_DIR/wiki"
echo "# wiki index" > "$RELAVA_KB_DIR/wiki/index.md"
bash "$SYNC_DIR/sync.sh" push > /dev/null
check "CLAUDE.md import line present before nuke" \
    grep -qxF "@$RELAVA_KB_DIR/wiki/index.md" "$RELAVA_CLAUDE_DIR/CLAUDE.md"

echo "--- nuke: delete the kb repo and the claude dir entirely ---"
rm -rf "$RELAVA_KB_DIR" "$RELAVA_CLAUDE_DIR"
check "kb repo actually gone before restore" test '!' -d "$RELAVA_KB_DIR"

echo "--- restore: re-run bootstrap ---"
bash "$SYNC_DIR/bootstrap.sh" "$WORKDIR/remote.git" > /dev/null

check "kb repo re-cloned" test -d "$RELAVA_KB_DIR/.git"
check "seeded agent re-symlinked" test -L "$RELAVA_CLAUDE_DIR/agents/seeded.md"
check "seeded agent content matches exactly" \
    content_matches "$RELAVA_CLAUDE_DIR/agents/seeded.md" "# seeded agent"
check "wiki re-cloned" test -f "$RELAVA_KB_DIR/wiki/index.md"
check "CLAUDE.md import line re-added after nuke" \
    grep -qxF "@$RELAVA_KB_DIR/wiki/index.md" "$RELAVA_CLAUDE_DIR/CLAUDE.md"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
