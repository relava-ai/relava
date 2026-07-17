# Personal LLM Wiki — Conventions

This is the schema layer for your personal LLM wiki (Karpathy's LLM-wiki pattern). It
defines how the wiki is structured and how Claude maintains it on your behalf. Read
it before any ingest / query / lint operation.

## Layers

1. **`sources/` — raw, immutable.** Curated inputs you've fed in: notes, articles,
   transcripts, exported threads. READ-ONLY. Never edit or delete a source once
   saved. One source per file, stable filename/slug.
2. **`pages/` — the wiki, LLM-owned.** Entity, concept, decision, and synthesis pages
   Claude creates and maintains on your behalf. One topic per file (keeps merges
   clean across machines). Cross-link with `[[wikilinks]]`. Every page carries
   frontmatter — see [frontmatter-schema.md](frontmatter-schema.md).
3. **`index.md` — the catalog.** One line per page: `- [[slug]] — one-line summary`.
   This is the only page meant to be auto-loaded every session (via your
   `~/.claude/CLAUDE.md`'s `@import`), so keep it **lean** — links and one-liners
   only, never page bodies.
4. **`log/` — chronological record.** One dated file per day: `log/YYYY-MM-DD.md`.
   Per-day files, not a single running log, so two machines never conflict on the tail.

## Operations

**Ingest** (a new source arrives):
1. Save the raw input under `sources/` (never edit it afterward).
2. Extract durable facts. Create/update the relevant `pages/` — one source often
   touches many. Set `created`/`last-validated` frontmatter on new pages.
3. Add/refresh `[[wikilinks]]` between affected pages.
4. Update `index.md` for any new/renamed page.
5. Append a one-line entry to today's `log/YYYY-MM-DD.md`.

**Query** (a question):
1. Consult `index.md`, open relevant `pages/`, follow `[[wikilinks]]`.
2. Answer with **citations** — link the page(s) and, through them, the underlying
   `sources/`.
3. If the answer needed real synthesis worth keeping, file it back as a new page +
   index entry + log line. Knowledge should compound, not evaporate.

**Lint** (periodic health check):
- Contradictions between pages → flag and reconcile (cite which source wins).
- Stale claims (`last-validated` far behind `created`, or a source superseded) →
  revalidate and bump `last-validated`, or update the page.
- Orphan pages (no inbound `[[links]]`) → link them in or retire them.
- Missing index entries or dead links → fix.

## Guardrails

- `sources/` is READ-ONLY. Pages interpret sources; they never replace them.
- **Every claim in `pages/` cites its source.** No uncited assertions.
- Keep `index.md` lean — it's the one file cheap enough to load every session.
- One topic per file everywhere (pages, sources, log-days) — this is what makes
  syncing across your own machines merge cleanly.
- **Index entries are for durable, cross-context patterns — not single-topic
  reference notes.** A page earns an `index.md` line only if it applies regardless
  of which project you're in (a workflow, a policy, a recurring technique). A page
  about one specific research topic, paper, or product stays fully queryable in
  `pages/` — cited by other pages, findable by search — without paying the
  "loaded every session" cost of an index entry. If a topic-specific page's ideas
  later generalize into a durable pattern, extract that synthesis into its own
  cross-cutting page and index *that*, not the narrow topic page.

## Viewing

Plain markdown with `[[wikilinks]]` — open this `wiki/` folder as an **Obsidian
vault** for a graph view if you want one. Git provides the audit trail; syncing
across machines happens automatically via the hooks wired by `bootstrap.sh`.
