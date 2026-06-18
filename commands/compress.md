# /compress — Save Session Log

Synthesise this session into a structured, searchable session log in your notes vault.
Follow every step exactly. (Paths below assume a notes-vault memory backend — adapt the
folder names to your own store.)

## Step 1 — Determine metadata

- **Date + time:** today's date (YYYY-MM-DD) and the approximate start time (HH-MM, 24h). If you cannot determine the start time, use the current time.
- **Slug:** 2–5 hyphenated lowercase words that identify the session's core topic (e.g. `delegation-setup`, `auth-refactor-part2`). Do not use underscores.
- **Filename:** `YYYY-MM-DD-HH-MM-{slug}.md` — all hyphens, no spaces.
- **Project:** the `project:` frontmatter value. Use the exact project folder name if the session was scoped to one project. Use a sanctioned shared value (e.g. `vault-wide`) for sessions that span multiple projects or are tooling/config work.
- **Topics:** 3–7 lowercase hyphenated tags capturing the main themes (e.g. `[auth, api, debugging]`).

## Step 2 — Write the file

Create the file at your session-log location:
```
<Session-Logs>/YYYY-MM-DD-HH-MM-{slug}.md
```

Use this exact template:

```markdown
---
type: session
date: YYYY-MM-DD
project: {project}
topics: [{topic1}, {topic2}, ...]
status: completed
tags: [{domain-tag}]
---

# Session: YYYY-MM-DD HH:MM — {slug}

## Quick Reference
**Topics:** topic1, topic2, topic3
**Projects:** Project-Name (or vault-wide)
**Outcome:** One sentence — what was accomplished or decided.
**Ref:** [[linked-note]] (if relevant)

## Decisions Made
- Decision with rationale. Be specific enough that a future session can act on it without re-deriving it.

## Key Learnings
- Non-obvious things that will be useful to remember. Skip obvious outcomes.

## Files Modified
- `path/to/file` — what changed and why

## Setup & Config
- Any environment changes (settings, installs, credentials, etc.) that persist beyond this session.

## Errors & Workarounds
- What failed and how it was resolved. Include tool/permission denials if they were surprising.

## Pending Tasks
- [ ] Unfinished work carried forward
- [x] Completed items (mark with [x] if carried from a prior session and completed here)

---

## Raw Session Log

[The full conversation is archived below for future searchability. Do not edit this section.]

{Summarise the session turn-by-turn. Each turn is 1–3 sentences. Focus on decisions, discoveries, and pivots — not mechanical steps. Use bold for turn numbers or labels (e.g. **Turn 3 — Audit**). Compress aggressively: 20 turns → ~15 lines is the target.}
```

## Step 3 — Tags

`tags:` should come from a closed, controlled vocabulary (keep a `tag-vocabulary` reference and add new recurring tags there first). Common shape: `[domain]` or `[domain, project]`, 2–4 tags max. Never use `session-log` as a tag (the `type: session` field covers this).

## Step 4 — Verify

Confirm the file was written and has valid YAML frontmatter. Report the filename and one-line outcome summary.

## Invariants

- **Session logs are append-only.** Never edit an existing session log — create a new one.
- **Dates are always YYYY-MM-DD.** No other formats.
- **`project:` must match exactly.** The value must match the project folder name (case-sensitive). Define sanctioned exceptions (e.g. `vault-wide`) explicitly.
- **Do not add a Quick Reference link to the project hub unless instructed** — a query-driven hub surfaces logs automatically via `project:` frontmatter.
