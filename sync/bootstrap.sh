#!/usr/bin/env bash
# One-time setup: wires this checkout of Relava into Claude Code for the
# current machine. Idempotent — safe to re-run.
#
# Run once:   bash sync/bootstrap.sh [remote-url]
#
# If a remote URL is given (as an argument or $RELAVA_KB_REMOTE) and the
# personal kb repo doesn't exist yet, it's cloned from there. Otherwise a
# fresh local-only repo is created (git init) — sync.sh already handles "no
# upstream configured" gracefully, so this still works standalone before a
# remote exists (single-machine use, or before the git-hosting decision is
# made — see EXECUTION_PLAN.md §0, S0.9).

set -uo pipefail

SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${RELAVA_KB_DIR:-$HOME/.relava/kb}"
REMOTE="${1:-${RELAVA_KB_REMOTE:-}}"
CLAUDE_DIR="${RELAVA_CLAUDE_DIR:-$HOME/.claude}"

echo "relava bootstrap: personal kb at $REPO"

# 1. Ensure the personal kb repo exists.
if [ -d "$REPO/.git" ]; then
    echo "  = kb repo already exists"
elif [ -n "$REMOTE" ]; then
    mkdir -p "$(dirname "$REPO")"
    git clone --quiet "$REMOTE" "$REPO"
    echo "  + cloned kb repo from $REMOTE"
else
    mkdir -p "$REPO"
    git -C "$REPO" init --quiet
    echo "  + created a fresh local kb repo (no remote configured yet)"
fi

# 2. Wire the three sync hooks into settings.json. Appends to each event's
#    hook list rather than overwriting it, so any pre-existing hooks the user
#    already has for these same events are preserved, not clobbered.
SETTINGS="$CLAUDE_DIR/settings.json"
mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
SYNC_DIR="$SYNC_DIR" python3 - "$SETTINGS" <<'PY'
import json, os, sys

path, sync_dir = sys.argv[1], os.environ["SYNC_DIR"]
sh = f"bash {sync_dir}/sync.sh"
commands = {
    "SessionStart":     sh,            # full: pull + push leftovers (also crash safety-net)
    "UserPromptSubmit": f"{sh} pull",  # start of turn: pull latest
    "Stop":             f"{sh} push",  # end of turn: push only if there is local work
}

with open(path) as f:
    cfg = json.load(f)

hooks = cfg.setdefault("hooks", {})
added = []
for event, cmd in commands.items():
    entries = hooks.setdefault(event, [])
    already = any(
        h.get("type") == "command" and h.get("command") == cmd
        for group in entries
        for h in group.get("hooks", [])
    )
    if not already:
        entries.append({"hooks": [{"type": "command", "command": cmd}]})
        added.append(event)

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")

print(f"  + wired hooks: {', '.join(added)}" if added else "  = hooks already wired")
PY

# 3. Bootstrap the personal wiki from wiki-template/, once, if not already
#    present. One-time like the kb repo itself — never re-copied on a later
#    run, so a user's own wiki content is never overwritten by template
#    updates. Runs before step 4 so the CLAUDE.md @import (in claude_code.sh,
#    gated on wiki/index.md existing) can activate on this same sync.
WIKI_TEMPLATE="$(cd "$SYNC_DIR/.." && pwd)/wiki-template"
if [ -d "$REPO/wiki" ]; then
    echo "  = personal wiki already bootstrapped"
elif [ -d "$WIKI_TEMPLATE" ]; then
    cp -R "$WIKI_TEMPLATE" "$REPO/wiki"
    echo "  + bootstrapped personal wiki from wiki-template/"
fi

# 3b. Seed agent-skill-template/'s agents and skills into the kb repo, one
#     item at a time (not the whole-directory check step 3 uses for wiki/,
#     since $REPO/agents and $REPO/skills may already exist with real
#     content — a user's own agents/skills, or items already seeded on a
#     previous run). Never overwrites an existing item of the same name; the
#     reconcile_dir() logic in claude_code.sh (already run via step 4 below)
#     is what actually symlinks whatever lands here into ~/.claude — this
#     step only needs to get the template content into the repo once.
AGENT_SKILL_TEMPLATE="$(cd "$SYNC_DIR/.." && pwd)/agent-skill-template"
if [ -d "$AGENT_SKILL_TEMPLATE" ]; then
    for kind in agents skills; do
        mkdir -p "$REPO/$kind"
        for item in "$AGENT_SKILL_TEMPLATE/$kind"/*; do
            [ -e "$item" ] || continue
            name_only="$(basename "$item")"
            if [ -e "$REPO/$kind/$name_only" ]; then
                echo "  = $kind/$name_only already present, not overwriting"
            else
                cp -R "$item" "$REPO/$kind/$name_only"
                echo "  + seeded $kind/$name_only from agent-skill-template/"
            fi
        done
    done
fi

# 4. Populate ~/.claude/{agents,skills,commands} etc. immediately, rather than
#    waiting for the next hook to fire.
bash "$SYNC_DIR/sync.sh" full

echo
echo "Done."
