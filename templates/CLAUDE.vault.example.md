# <VaultName> — Claude Code Memory

This file is Claude Code's **always-loaded lean core** for this vault. Every line is a
recurring per-session token cost, so only content needed every session belongs here. Reference
depth lives in the vault graph — fetch it via the **Memory Map** below. Claude Code does NOT
auto-follow `[[wikilinks]]`, so load those explicitly when the work calls for it.

---

## Environment

- **OS:** `<your-os>` (e.g. macOS / Linux distro / Windows)
- **Shell:** `<your-shell>` (e.g. zsh / fish / PowerShell)
- **Vault path:** `<vault-root>` (fill in the real absolute path per machine)
- **Terminal / editor notes:** `<anything project-specific: which terminal app, hotkeys, etc.>`

---

## Vault Identity

- **Name:** `<VaultName>`
- **Purpose:** `<one sentence — what this vault is for>`
- **Philosophy:** **Write Once, Surface Everywhere.** Frontmatter added once to a note makes it
  appear automatically in all relevant queries, dashboards, and project hubs. No manual linking.
  The vault organizes itself.

---

## Folder Structure

Three-layer system: **Capture** → `+Inbox/` · **Process** → `Areas/` · **Surface** →
an index note, dashboards, project hubs (automatic via Dataview).

- `+Inbox/` — quick captures (process within 24–48h).
- `Areas/Work/` — `Projects/[Name]/` (hub `.md` + `Assets/` + `Meetings/`) · `Meetings/`
  (standalone) · `Session-Logs/` (from `/compress`) · an index note for the work area.
- `Areas/` (other) — whatever other life areas you track (Personal, Health, Hobbies, …).
- `Calendar/` — `Daily/` (YYYY-MM-DD) · `Weekly/` (YYYY-W##) · `Monthly/` (YYYY-MM).
- `System/` — `Templates/` · `Dashboards/` · `References/` (stable setup/reference docs).
- `CLAUDE.md` (this lean core) · optionally a `CLAUDE-Archive.md` for superseded content.

Session logs: `Areas/Work/Session-Logs/YYYY-MM-DD-HH-MM-<slug>.md`.

---

## Frontmatter Standards

Every note has YAML frontmatter (`type`, `date`, `status`, + domain fields) — the engine of
"Write Once, Surface Everywhere." **`type` vocabulary:** `meeting | project | note | session |
daily | weekly | monthly` (extend with your own: `adr | pattern | spec | plan | …`).

Minimal template:

```yaml
---
type: note        # meeting | project | note | session | daily | weekly | monthly | ...
date: YYYY-MM-DD
status: active     # active | on-hold | completed | archived
project: <ProjectName>   # only if this note belongs to a project
tags: [domain, topic]
---
```

---

## Conventions

1. **Inbox is temporary** — `+Inbox/` is a staging area, not storage. Process it regularly
   (`/inbox-process`).
2. **Project names are case-sensitive** — the `project:` frontmatter value must match the
   folder name in `Areas/Work/Projects/` exactly.
3. **Dates are always YYYY-MM-DD** — no exceptions, no other formats.
4. **Never manually link** — let Dataview surface connections via frontmatter queries.
5. **Session logs are append-only** — never edit a session log after creation. Create a new one.
6. **Session brackets:** run `/resume` at session start, `/wrap` before ending — `/wrap` is the
   unified close (preserve-check + `/compress` + `/sync-config`, skipping what isn't needed).
7. **Conductor delegates, cheaper models execute** — the main-loop model orchestrates, plans,
   judges, and synthesizes; it delegates token-heavy bounded work (research scans, repetitive
   edits, test runs, log reduction) to cheaper sonnet/haiku subagents.
8. **Quick-recap status line** — end every work-completing response with a final status line:
   🟢 finished · 🟡 non-routine follow-up remains (name it) · 🔴 blocked on user input.
9. **CLAUDE.md is the lean core** — holds only what's needed every session. Reference depth
   lives in vault notes, fetched via the Memory Map. Permanent decisions go here via
   `/preserve`; they override session memory.

---

## Memory Map — where depth lives

Claude Code does NOT auto-follow `[[wikilinks]]`. Fetch these explicitly when the work calls
for them:

| When working on… | Read |
|---|---|
| Orientation: priorities / areas of life | `<path to your orientation/context-map note>` *(read at session start)* |
| Frontmatter details (creating/editing notes) | `System/References/<frontmatter-standards-note>` |
| Claude Code setup for this vault (MCP, hooks, model) | `System/References/<claude-code-setup-note>` |
| Multi-machine sync, if applicable | `System/References/<multi-machine-sync-note>` |
| Tag vocabulary, if you use a controlled tag list | `System/References/<tag-vocabulary-note>` |
| `<ProjectName>` project | `Areas/Work/Projects/<ProjectName>/<ProjectName>.md` |
| `<another recurring area, e.g. home infra>` | `Areas/<Area>/<Note>.md` |

---

## Active Projects

*(Update as projects are added or completed)*

### `<ProjectName>`
- **Status:** `<active | on-hold | completed>` · **Path:** `Areas/Work/Projects/<ProjectName>/`
- `<one-line description of what it is>`

*Add one block per active project. Move completed/on-hold projects to an archive section or
note rather than deleting the history.*
