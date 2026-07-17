---
name: plan
description: "Workflow for non-trivial multi-step work: write a plan doc (tasks + subtasks + dependencies) before touching implementation, sync it to GitHub issues (create/update, with acceptance criteria and dependency links), then execute exactly one item at a time — never auto-implement a whole plan or phase without asking first. Use before starting any multi-step feature, phase, or body of work that will span multiple commits/PRs. Not needed for a single small fix or a one-line change — don't over-apply this to trivial requests."
---

# plan — plan-first workflow

Four steps, in order, for any work substantial enough to span more than one commit or
PR: **plan → doc → issues → execute one at a time.**

## When this applies

Multi-step work: a new feature, a phase/milestone, anything touching more than one
file in a non-trivial way, or anything the user describes as more than a single fix.
Don't invoke this ceremony for a one-line change or an isolated bug fix — use judgment,
and if genuinely unsure whether something crosses the threshold, err toward the
lighter-weight path and let the user redirect if they wanted more structure.

## Step 1 — Write the plan doc

Before any implementation, produce (or update) a document listing every task and
subtask, **with explicit dependencies** — what blocks what, not just a flat list.

Where it lives:
- If the project already has a planning-doc convention, extend that rather than
  inventing a new one. (Some projects split this across a stable narrative doc — e.g.
  `ROADMAP.md` — and a granular per-task checklist — e.g. `TASKS.md` — with IDs
  cross-referencing between them; if you're working in a project like that, follow its
  existing split rather than starting a third doc.)
- Otherwise, default to `plan.md` at the repo root (or the most relevant subdirectory
  for a scoped feature): one line per task, sub-bullets for subtasks, and a
  `Blocked by: <task>` note wherever a real dependency exists.

Get the user's sign-off on the plan before moving to Step 2 — unless they've already
described the scope in enough detail that the plan is a formality (use judgment, but
don't skip silently past genuinely open scope questions).

## Step 2 — Sync to GitHub issues

For each task — and each subtask substantial enough to track independently — in the
plan doc:

1. Check `gh issue list` for an existing issue before creating a new one. Never
   duplicate.
2. Create missing issues with:
   - A `Part of #<parent>` line if there's a natural parent/phase issue.
   - A `## Task` section describing the work (pull this from the plan doc, don't just
     paste the one-line title).
   - A `## Acceptance criteria` checklist derived from the plan doc's detail — concrete
     and checkable, not vague.
3. Record dependencies explicitly:
   - Parent/child (a phase issue and its sub-tasks): GitHub's sub-issues API —
     `gh api -X POST repos/<owner>/<repo>/issues/<parent>/sub_issues -F
     sub_issue_id=<numeric-id>` (note: `-F` for the numeric id, not `-f` — `-f` sends
     it as a string and 422s).
   - Peer dependency (task B can't start until task A lands, but they're not
     parent/child): a plain `Blocked by #<n>` line in the body.
4. **This is a standing rule, not a one-time pass**: whenever the plan doc changes
   later — scope added, removed, or re-sequenced — treat syncing the corresponding
   issues as part of that same edit, not a separate cleanup task to get to eventually.
   Before considering a planning update "done," check whether any issue is now stale
   (status, scope, or dependency) and fix it in the same pass.

Before inventing issue-body formatting from scratch, check a couple of the repo's own
recent closed issues for tone and structure — reuse whatever convention already exists
rather than introducing a new one.

## Step 3 — Execute one item at a time

Once issues exist for the current batch of work, implement **exactly one unblocked
item per pass**. Before starting the next item:

- Confirm the previous one actually landed (merged, or otherwise confirmed complete)
  — don't queue the next item on an assumption that the last one is fine.
- Never silently implement multiple items, or a whole phase, in one pass. If there's a
  genuine efficiency reason to bundle two items (e.g. they're trivially small and
  touch the same file), ask first and get explicit agreement before doing so — don't
  decide unilaterally that bundling is fine this time.

If the project has its own execution machinery for this step (e.g. a dedicated
implementer-style agent that runs the build/test/review loop per item), hand off to
that; this skill governs the planning-and-tracking layer above it, not the
implementation mechanics themselves.

## Quick reference

```
1. PLAN   — tasks + subtasks + dependencies, written down, user sign-off
2. DOC    — a plan.md (or the project's existing equivalent)
3. ISSUES — gh issue list check → create/update, with acceptance criteria + dependency links
4. EXECUTE — one unblocked item at a time; confirm landed before starting the next
```
