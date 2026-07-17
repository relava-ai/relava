# Wiki page frontmatter schema

Every page in `pages/` carries YAML frontmatter with these fields:

```yaml
---
type: concept | decision | entity | synthesis
created: YYYY-MM-DD
last-validated: YYYY-MM-DD
---
```

- **`type`** — what kind of page this is:
  - `concept` — a durable definition or piece of knowledge (a technique, a term, how something works)
  - `decision` — a choice made and why, including rejected alternatives
  - `entity` — a person, project, system, or tool this wiki refers to repeatedly
  - `synthesis` — a cross-cutting summary that ties multiple sources/pages together
- **`created`** — the date this page was first written
- **`last-validated`** — the date someone (or an LLM lint pass) last confirmed this
  page still reflects its sources. Used by a freshness/TTL lint pass to flag stale
  pages for revalidation — a page whose `last-validated` falls too far behind is a
  candidate for re-checking, not automatic deletion.

Update `last-validated` whenever a page's claims are re-confirmed against current
sources, even if the text itself doesn't change.
