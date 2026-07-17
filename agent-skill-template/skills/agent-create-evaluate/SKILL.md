---
name: agent-create-evaluate
description: "Evaluation criteria for newly authored Claude Code agent/skill files (agent.md, SKILL.md). Used by the agent-create-evaluator agent as its grading standard: single responsibility, skill usage, evaluator-pairing, tool least-privilege, placement correctness, and frontmatter validity."
---

# agent-create-evaluate — grading standard

Grades a set of files produced by `agent-creator` (or anyone hand-authoring an agent
per the `agent-create` skill): the primary agent, its companion skill(s), and — if
applicable — its paired `<name>-evaluator` agent and `<name>-evaluate` skill.

## Frontmatter validity

- Agent: `name` is kebab-case and matches the filename; `description` is present and
  non-empty; `tools` (if present) is a comma-separated list of real tool names, not a
  placeholder; `model` is set (`inherit` or a specific justified model).
- Skill: `name` is kebab-case and **matches the containing directory name exactly**;
  `description` states both what it does and when to use it.

Any mismatch or missing required field is **CRITICAL**.

## Single responsibility

Read the agent's `description` and system prompt. Flag as **MAJOR** if:
- The description joins two or more unrelated verb-object pairs with "and" (e.g.
  "reviews code and deploys it").
- The system prompt's own workflow contains phases that belong to visibly different
  jobs (e.g. a code-writing phase followed by an unrelated notification/deployment
  phase with no orchestration boundary between them).

A multi-phase workflow that stays within one coherent job (implement → test → review
loop → report, all in service of "build this module") is fine — that's one job with
several steps, not multiple hats.

## Skill usage

Flag as **MINOR** if the agent's system prompt contains a substantial reusable
procedure (more than a few steps that could plausibly recur across other agents)
inlined directly rather than factored into a companion skill it references. Atomic
agents with no reusable procedure are exempt — don't flag skill-less agents whose job
is genuinely a single fixed action.

## Evaluator-pairing

Determine whether the primary agent produces reviewable output (code, docs, config,
structured data, other agent/skill definitions). If yes, verify:

- A `<name>-evaluate` skill exists with objective PASS/FAIL criteria for that output
  type.
- A `<name>-evaluator` agent exists, evaluate-only (no `Write`/`Edit` in its `tools`),
  applying those criteria.
- The primary agent's own workflow section actually invokes the evaluator in a loop:
  fix-on-FAIL, re-invoke, cap at ~3 cycles before escalating to the user. A pairing
  that exists but is never actually wired into the primary agent's workflow doesn't
  satisfy this rule.

Missing any of the three when the exception (pure read-only research/reporting) doesn't
apply is **CRITICAL**.

## Tool least-privilege

- Evaluator agents (`<name>-evaluator`) carrying `Write` or `Edit` is **CRITICAL** —
  defeats the purpose of a separate evaluator.
- Any agent granted a tool its own workflow never references is **MINOR**.

## Placement correctness

- Verify the file landed in the scope justified by `agent-create`'s placement rule:
  project-specific agents/skills in `<project>/.claude/`, generically useful ones in
  `~/.claude/`. A generic-sounding agent placed in a project's `.claude/` (or vice
  versa) without a stated justification is **MAJOR**.
- Verify no existing, unrelated file was silently overwritten (check whether this was a
  deliberate update vs. an accidental collision, e.g. via recent file mtime plus
  content diff if uncertain). An unjustified overwrite is **CRITICAL**.

## Leanness

`SKILL.md` bodies meaningfully over ~500 lines without a `references/` split, or
bundled resources (`scripts/`, `references/`, `assets/`) that nothing in `SKILL.md`
actually points to, are **MINOR**.

## PASS / FAIL criteria

A file set **PASSES** if ALL of the following hold:

1. Frontmatter validity: zero CRITICAL
2. Single responsibility: zero MAJOR
3. Evaluator-pairing: zero CRITICAL (pairing present and actually wired in, when
   applicable)
4. Tool least-privilege: zero CRITICAL
5. Placement correctness: zero CRITICAL

MINOR items don't block PASS but should still be reported — they're worth fixing when
convenient, not worth blocking on.

A file set **FAILS** if any CRITICAL item exists anywhere, or any MAJOR item exists in
single responsibility or evaluator-pairing.
