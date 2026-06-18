# /preserve — Commit a Lasting Decision or Learning

Route durable knowledge into the right layer of your memory backend. The goal is to keep the
always-loaded **core instruction file** lean and push all depth to separate notes. (Paths are
illustrative — adapt to your own store: a notes vault, a docs folder, etc.)

## Routing Decision

Ask: **Will this be needed every session, or only when working on a specific topic?**

| Content type | Route |
|---|---|
| A rule or convention that applies to every session (a new naming rule, a permanent workflow step, a standing constraint) | → **Core file** |
| Detailed reference material — architecture decisions, tool mechanics, setup docs, playbook entries, how-to guides | → **Depth note** + a pointer in the core file's index |
| A decision that supersedes something already in the core file | → **Update the core file** in-place; archive the superseded content if it was load-bearing |

When in doubt, choose the depth note. The core file is loaded every session — keep it lean.

---

## Route A — Core file

1. Read the core file fully before editing.
2. Find the right section (conventions, project state, recurring reminders, etc.).
3. Add the content. Be terse — one bullet or a short paragraph. If it's long, summarise here and route the detail to a depth note (Route B) with a pointer.
4. If you're adding to a numbered convention list, assign the next sequential number.
5. Check leanness: if adding pushes the core file past its size budget, trim an equivalent amount elsewhere (archive superseded content).
6. Do NOT add the same information twice. If it updates an existing entry, edit in-place.

---

## Route B — Depth note

1. Create a new note in your depth-notes location (or update an existing one).
2. Add proper frontmatter, e.g.:
```yaml
---
type: note
date: YYYY-MM-DD
status: active
tags: [{relevant-tags}]
aliases: [{Human Readable Title}]
---
```
3. Write the full depth content — detail, examples, tables, test procedures, edge cases.
4. Add a one-line pointer in your memory index. Format: `- [Title](file) — one-line hook`.
5. Add a row to the lookup/index table in the core file pointing to the new note.
6. Optionally add a 1-line mention in the core file's recurring-notes section if it must be top-of-mind every session (e.g. a renewal date, a standing caveat).

---

## Route C — Update / Archive

1. Read the existing entry in the core file.
2. Edit it in-place with the new decision.
3. If the old content was significant and not simply wrong, move it to an archive file with a dated header: `## Superseded YYYY-MM-DD — {what it was}`.
4. Note the supersession in the update (e.g. "supersedes the YYYY-MM-DD decision to…").

---

## After routing

Tell the user:
- Which route was taken and why
- Exactly what was added/changed (file path + section)
- The net line-count delta for the core file if it was touched
- Whether an index pointer was added
