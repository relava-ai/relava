#!/usr/bin/env bash
# Regression test: bootstrap.sh must seed agent-skill-template/'s agents and
# skills into the kb repo on first run (per item, idempotent — never
# overwrites an existing item, whether that's a previous seed or a user's
# own content with the same name), and the existing reconcile_dir() sync
# logic must then symlink whatever landed there into ~/.claude.
#
# Run manually: bash sync/tests/agent-skill-seed.sh
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

echo "--- fresh bootstrap, local-only kb (no remote) ---"
bash "$SYNC_DIR/bootstrap.sh" > /dev/null

for agent in agent-creator agent-create-evaluator skill-creator skill-create-evaluator; do
    check "$agent.md seeded into kb repo" test -f "$RELAVA_KB_DIR/agents/$agent.md"
    check "$agent.md symlinked into \$CLAUDE_DIR" test -L "$RELAVA_CLAUDE_DIR/agents/$agent.md"
done
for skill in agent-create agent-create-evaluate plan skill-create skill-create-evaluate; do
    check "$skill/ seeded into kb repo" test -d "$RELAVA_KB_DIR/skills/$skill"
    check "$skill/ symlinked into \$CLAUDE_DIR" test -L "$RELAVA_CLAUDE_DIR/skills/$skill"
done

echo "--- a user's own pre-existing item with a colliding name must survive ---"
rm -rf "$RELAVA_KB_DIR" "$RELAVA_CLAUDE_DIR"
mkdir -p "$RELAVA_KB_DIR/skills/plan"
echo "# my own custom plan skill" > "$RELAVA_KB_DIR/skills/plan/SKILL.md"
git -C "$RELAVA_KB_DIR" init --quiet
bash "$SYNC_DIR/bootstrap.sh" > /dev/null

check "user's own plan skill NOT overwritten" \
    content_matches "$RELAVA_KB_DIR/skills/plan/SKILL.md" "# my own custom plan skill"
check "every other template skill still seeded despite the collision" \
    test -d "$RELAVA_KB_DIR/skills/skill-create"

echo "--- re-run bootstrap: seeding must be idempotent (no errors, no duplication) ---"
bash "$SYNC_DIR/bootstrap.sh" > /dev/null
check "agent-creator.md still a single file after re-bootstrap" test -f "$RELAVA_KB_DIR/agents/agent-creator.md"
check "user's own plan skill still untouched after re-bootstrap" \
    content_matches "$RELAVA_KB_DIR/skills/plan/SKILL.md" "# my own custom plan skill"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
