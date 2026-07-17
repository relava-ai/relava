---
name: agent-create
description: "Methodology for authoring a new Claude Code agent, its companion skill(s), and — when the agent produces reviewable output — its paired evaluator agent and evaluate skill. Covers single-responsibility scoping, least-privilege tool grants, trigger-clear descriptions, and where the files should live (user space vs. project space). Used by the agent-creator agent as its authoring standard; consult directly when hand-writing an agent.md or SKILL.md."
---

# agent-create — agent authoring standard

## The organizing distinction

A **skill** is *how* to do a specific thing — a reusable procedure, standard, or
methodology. A **agent** is *what* it does — a scoped actor with a specific job, which
consults one or more skills to get there. Get this backwards (procedural detail baked
into the agent's own prompt instead of a skill, or a "skill" that's really just an
agent persona with no reusable how-to content) and both become harder to reuse and
harder to evaluate independently. Design the skill(s) first, then the agent that uses
them.

## Single responsibility — no multiple hats

An agent gets **one job**. If the description you're working from needs "and" to join
two unrelated verbs — "an agent that reviews code and deploys it," "an agent that
writes docs and files GitHub issues and pings Slack" — that's two or three agents, not
one. Split it. Each agent can still invoke the others via the `Agent` tool if
orchestration is genuinely needed, but the responsibility boundary between them should
be clean enough that each one's `description` reads as a single sentence with a single
verb-object pair.

The test: could you hand this agent's system prompt to a new specialist hire and have
them understand their job in one read, without "...and also..." appearing? If not,
split it.

This constraint applies recursively to `agent-creator` itself — if a request would
make it design, write files, review its own output, AND do something unrelated like
deploying or notifying, that unrelated part is a different agent's job.

## Skill usage

An agent should externalize its "how" into skill(s) rather than embedding a full
procedure directly in its own system prompt. Concretely:

- If a skill covering the agent's core procedure already exists, reference it — don't
  duplicate its content into the agent's prompt.
- If it doesn't exist yet, author it in the same pass as the agent (this skill's own
  companions — `plan`, `agent-create-evaluate` — were authored exactly this way).
- An agent may consult multiple skills without that meaning multiple jobs — e.g. an
  agent whose one job is "implement this module end-to-end" might read a coding-
  standards skill for style/conventions and invoke a separate knowledge-capture skill
  to record what it learned. Several skills, still one job.
- A genuinely atomic agent (e.g., one whose entire job is "run this one fixed command
  and report the result") doesn't need an invented skill just to satisfy this rule —
  don't force a skill into existence for something with no reusable procedure behind
  it.

## The evaluator-pairing rule

If the agent you're designing **produces output that could be wrong, incomplete, or
non-compliant with a standard** — code, docs, config, structured data, or (recursively)
other agent/skill definitions — it must ship with:

1. A dedicated `<name>-evaluate` skill: objective PASS/FAIL grading criteria for that
   specific output type. See `agent-create-evaluate` (this template's own evaluate
   skill) for a concrete worked example of the shape — concrete criteria, PASS/FAIL
   rollup, no vague "looks good" judgment calls.
2. A dedicated `<name>-evaluator` agent: evaluate-only (`Read, Grep, Glob, Bash` — never
   `Write`/`Edit`, it can't fix what it's grading), applies the evaluate skill's
   criteria, and returns a structured report. Reuse this exact report shape for
   consistency across every evaluator in this ecosystem:

   ```
   {DOMAIN} EVALUATION REPORT
   File: {path}
   ═══════════════════════════════════════════════════════

   OVERALL: {PASS | FAIL}
     {criterion 1} : {PASS | FAIL}
     {criterion 2} : {PASS | FAIL}
     ...

   REQUIRED FIXES  (must resolve before PASS)
     ─ [CRITICAL|MAJOR|MINOR] {CATEGORY} — {what/where}
       Action: {exact fix}

   VERIFIED  (confirmed correct)
     ✓ {what was checked and passed}
   ```

3. A workflow section in the primary agent's own prompt that actually invokes the
   evaluator in a loop: implement → invoke evaluator → if `FAIL`, fix every
   `REQUIRED FIXES` item (no skipping/deferring) → re-invoke only the evaluator that
   failed → repeat until `PASS`. Cap it: if the same violation survives 3 consecutive
   cycles, stop and ask the user instead of iterating forever — `agent-creator`
   (this template's own agent) states this rule explicitly in its own prompt; copy
   the same shape into any new agent that has this loop.

**Exception**: pure read-only research/reporting agents (e.g., a codebase-search agent
that returns findings but writes nothing durable) don't produce a gradeable artifact —
no evaluator needed. When genuinely unsure, ask: "could this output plausibly need a
human or a second pass to check it's right/complete/safe?" If yes, pair it with an
evaluator.

## Tool grants — least privilege

List only the tools the agent actually uses, comma-separated in frontmatter (e.g.
`tools: Read, Edit, Write, Grep, Glob, Bash, Skill, Agent` for an agent that writes
files and delegates to sub-agents). Evaluator agents in particular: `Read, Grep,
Glob, Bash` only, ever — granting `Write`/`Edit` to something whose entire job is
independent judgment defeats the point of having a separate evaluator.

## Trigger-clear description

The `description:` frontmatter field is the dispatch mechanism other agents (and you)
use to decide when to reach for this one. State concretely:

- When to use it (concrete trigger phrases/situations, not abstract categories)
- What it's explicitly *not* for (a scope boundary) — e.g. "Not for open-ended
  design — the target and scope should already be decided" is the kind of concrete
  exclusion that keeps an agent from getting reached for the wrong job

Lean slightly assertive/"pushy" rather than vague — the installed `skill-creator`
plugin (`~/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/`)
notes that Claude tends to under-trigger skills with a wishy-washy description; the
same applies to agent descriptions read by you as dispatcher.

## Placement — where files go

**Default: user space** — `~/.claude/agents/<name>.md`, `~/.claude/skills/<name>/SKILL.md`.
Most agents/skills are generically useful across whatever project you're in, and user
space makes them available everywhere without polluting any one repo's checked-in
`.claude/`.

**Project space** — `<project-root>/.claude/agents/`, `<project-root>/.claude/skills/`
— only when either holds:

- The agent is inherently specific to that project: it reads/writes project-specific
  files, encodes project-specific invariants, or reasons about a project's own planning
  docs. (For example, a `phase-gate` agent that reads one project's own phased build
  plan and enforces that project's own exit criteria — meaningless in any other repo.)
- The user explicitly asks for project scope.

If genuinely unsure which applies, ask rather than guess — the two scopes have very
different blast radii (one repo vs. every project on the machine).

**Never silently overwrite** an existing agent/skill with the same name in either
scope. Check first: if it's the same thing being knowingly updated, proceed; if it's a
genuine name collision with something unrelated, either pick a more specific name or
flag the conflict and ask.

## Frontmatter checklists

**Agent** (`<name>.md`):
- `name`: kebab-case, matches the filename (minus `.md`)
- `description`: trigger-clear, states the scope boundary (see above)
- `tools`: minimal, comma-separated inline (omit the field entirely only if the agent
  genuinely needs unrestricted access — rare)
- `model: inherit` unless a specific model is deliberately justified (e.g. a cheap,
  high-volume evaluator that doesn't need the primary model's full capability)

**Skill** (`<name>/SKILL.md`):
- `name`: kebab-case, **must match the containing directory name exactly** — Claude
  Code resolves skills by directory, a mismatch silently breaks invocation
- `description`: states both *what it does* and *when to use it* — all "when to use"
  information belongs here, not buried in the body

## Keep it lean

Target under ~500 lines for a `SKILL.md` body (the installed `skill-creator` plugin's
own guidance). If a skill is approaching that and has genuinely large reference
material, split it into a `references/` subdirectory and point to it clearly rather
than inlining everything — progressive disclosure, not everything loaded every time.

## Worked example

**Self-referential**: `agent-creator` (`~/.claude/agents/agent-creator.md`) + this
skill + `agent-create-evaluator`/`agent-create-evaluate` — built by hand following
this exact standard, since nothing existed yet to bootstrap from. Read any of these
four files directly for a concrete instance of every rule above applied together:
single job, skill-first design, a wired-in evaluator loop, least-privilege tools, a
trigger-clear description, user-space placement.
