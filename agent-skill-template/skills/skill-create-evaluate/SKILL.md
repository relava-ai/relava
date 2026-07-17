---
name: skill-create-evaluate
description: "Evaluation criteria for a newly authored standalone Claude Code skill (SKILL.md, no companion agent). Used by the skill-create-evaluator agent as its grading standard: single procedure, trigger-clear description, agent-vs-skill correctness, placement, frontmatter validity, and leanness."
---

# skill-create-evaluate — grading standard

Grades a single `SKILL.md` produced by `skill-creator` (or anyone hand-authoring a
standalone skill per the `skill-create` skill).

## Frontmatter validity

- `name` is kebab-case and **matches the containing directory name exactly**.
- `description` is present, non-empty, and states both what the skill does and when
  to use it.
- No `tools:` field present (skills don't carry tool grants — that's an agent-only
  frontmatter field; its presence here is **MINOR**, likely copy-paste residue).

Any `name`/`description` problem is **CRITICAL**.

## Single procedure

Read the skill's body. Flag as **MAJOR** if it visibly bundles two or more unrelated
"how to X" procedures with no single coherent topic tying them together (distinct
from a single procedure broken into multiple sections/steps, which is fine).

## Trigger-clear description

Flag as **MAJOR** if the `description` is vague enough that it's unclear when this
skill should get consulted (no concrete trigger phrases/situations), or if it's
hedged/wishy-washy in a way likely to under-trigger it.

Flag as **MINOR** if there's a plausible-sounding adjacent alternative (another skill,
or an agent doing something similar) that the description doesn't distinguish itself
from, when that distinction is genuinely likely to matter.

## Agent-vs-skill correctness

Read the skill's actual content. Flag as **MAJOR** if it describes something that
reads as an ongoing autonomous actor with its own job (an agent's shape) rather than
reference material/a procedure to be consulted — i.e. `skill-creator` should have
deferred to `agent-create`/`agent-creator`'s territory instead of authoring this as a
standalone skill.

## Placement correctness

- Verify the file landed in the scope justified by `skill-create`'s placement rule:
  project-specific skills in `<project>/.claude/skills/`, generically useful ones in
  `~/.claude/skills/`. A generic-sounding skill placed in a project's `.claude/` (or
  vice versa) without a stated justification is **MAJOR**.
- Verify no existing, unrelated file was silently overwritten (check recent file
  mtime plus content diff, or `git log --diff-filter=A -- <path>`, if unclear whether
  this was a deliberate update vs. an accidental collision). An unjustified overwrite
  is **CRITICAL**.

## Leanness

`SKILL.md` body meaningfully over ~500 lines without a `references/` split, or
bundled resources (`scripts/`, `references/`, `assets/`) that nothing in `SKILL.md`
actually points to, are **MINOR**.

## PASS / FAIL criteria

A skill **PASSES** if ALL of the following hold:

1. Frontmatter validity: zero CRITICAL
2. Single procedure: zero MAJOR
3. Trigger-clear description: zero MAJOR
4. Agent-vs-skill correctness: zero MAJOR
5. Placement correctness: zero CRITICAL

MINOR items don't block PASS but should still be reported — worth fixing when
convenient, not worth blocking on.

A skill **FAILS** if any CRITICAL item exists anywhere, or any MAJOR item exists in
single procedure or agent-vs-skill correctness.
