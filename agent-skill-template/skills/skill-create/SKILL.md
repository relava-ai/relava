---
name: skill-create
description: "Methodology for authoring a standalone Claude Code skill — one with no dedicated agent attached. Covers single-procedure scoping, trigger-clear descriptions, placement (user space vs. project space), and when a request actually needs an agent instead of (or in addition to) a skill. Used by the skill-creator agent as its authoring standard; consult directly when hand-writing a SKILL.md with no companion agent."
---

# skill-create — standalone skill authoring standard

## When this applies, and when it doesn't

A **skill** is *how* to do a specific thing — a reusable procedure, standard, or
methodology, consulted by whichever agent (or you, directly) needs it. This standard
covers the case where a skill is the *whole* deliverable: no dedicated agent gets
created alongside it.

That's not always the right call. If the request actually implies an ongoing,
autonomous actor with a specific job — something that should be *dispatched to*
rather than *consulted* — that's `agent-create`'s territory instead (which itself
authors companion skills as part of an agent's design, when the agent needs one).
Concretely: does this need to run end-to-end on its own initiative when triggered, or
is it reference material something else reads before acting? The former is an agent
(with an attached skill if it has real procedural content); the latter is a
standalone skill. If genuinely unsure, ask rather than default to whichever is less
work to build.

**This template also ships `agent-creator`.** If a request is ambiguous between the
two, or the answer is "both" (an agent that needs a new skill written for it), that's
`agent-creator`'s job, not this one — it authors skills as part of its own workflow
when an agent needs one. Reach for `skill-creator` specifically when nothing
agent-shaped is being requested at all.

## Single procedure — no bundled how-tos

A skill covers **one coherent procedure or standard**. If what's being asked for is
really two unrelated "how to X" and "how to Y" with no natural single topic tying them
together, that's two skills, not one with two sections bolted together. The test:
could someone new to it read this `SKILL.md` and understand it covers one topic,
without an internal "Part 1 / Part 2, unrelated" structure? If not, split it.

A skill *can* have multiple sections/steps (see `plan`'s own four-step structure, or
this skill's own multi-section shape) — that's fine as long as they all serve one
coherent procedure, not several independent ones sharing a file for convenience.

## Trigger-clear description

Same discipline as an agent's `description`, adapted for a skill: state concretely
*what it does* and *when to use it* — Claude Code resolves which skill to consult
based on this field, so vague language means it won't get reached for when it should.
Lean assertive rather than hedged; a skill's own installed-plugin precedent
(Anthropic's marketplace `skill-creator`, if present on a given machine) notes the
same failure mode — wishy-washy descriptions under-trigger.

Include a scope boundary where it matters: what this skill is explicitly *not* for,
especially if there's a plausible-sounding but wrong alternative (see the
"agent-create instead" case above — a good `skill-create`-authored skill's
description should make clear whether it also covers, or explicitly excludes, an
adjacent case someone might confuse it with).

## Placement — where files go

Identical rule to `agent-create`: **default to user space**
(`~/.claude/skills/<name>/SKILL.md`) unless the skill is inherently specific to one
project (encodes that project's own invariants, reads that project's own planning
docs) or the user explicitly asks for project scope. Never silently overwrite an
existing skill of the same name — check first.

## Frontmatter checklist

- `name`: kebab-case, **must match the containing directory name exactly** — a
  mismatch silently breaks invocation.
- `description`: states both what it does and when to use it, including any scope
  boundary that disambiguates it from an adjacent skill or from needing an agent
  instead (see above).

No `tools:` field — skills don't carry tool grants; whatever agent or session
consults a skill uses its own tools.

## Keep it lean

Target under ~500 lines for the `SKILL.md` body. If a skill is approaching that with
genuinely large reference material, split it into a `references/` subdirectory and
point to it clearly rather than inlining everything.

## Worked example

**Self-referential**: this skill itself, plus `skill-creator` (the agent that follows
it), `skill-create-evaluator`, and `skill-create-evaluate` — the same self-bootstrap
pattern `agent-create`/`agent-creator` used, since nothing skill-specific existed yet
to build from. Read any of these four for a concrete instance of every rule above
applied together.
