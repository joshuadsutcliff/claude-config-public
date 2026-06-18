# /resume — Orient at Session Start

Load context for this session: read orientation, recent session history, and any relevant
depth notes. Run this at the start of every session before doing any work. (Paths are
illustrative — adapt to your own memory backend.)

## Arguments (optional)

- No args: `/resume` — load the last 3 session logs
- Number only: `/resume 10` — load the last 10 session logs
- Search term only: `/resume auth` — load last 3 logs + search session logs for "auth"
- Both: `/resume 5 auth` — load last 5 logs + search for "auth"

Parse `$ARGUMENTS` to determine count (first numeric token, default 3) and search term (remaining text, if any).

## Step 1 — Orientation

Read your orientation note (the who/what/priorities map). This is always required.

## Step 2 — Recent session logs

Find the N most recent session logs in your session-logs location (sort by filename descending — if filenames are `YYYY-MM-DD-HH-MM-slug`, lexicographic order = chronological order).

For each log, read only the top section (up to and including `## Pending Tasks`) — do NOT read the `## Raw Session Log` section unless investigating something specific. The Quick Reference + Decisions + Learnings + Pending Tasks is designed for fast, low-token scanning.

## Step 3 — Search (if a search term was provided)

If a search term was given, search session logs for files whose content matches the term. Read the Quick Reference section of any matching logs not already loaded in Step 2.

## Step 4 — Present orientation

Give the user a concise summary covering:

1. **Active projects and current status** (from the orientation note + recent logs)
2. **What was accomplished recently** (from the last 1–2 session logs)
3. **Pending tasks** — a consolidated list of `[ ]` items from the loaded logs, deduplicated and ordered most-recent first
4. **Any blockers or time-sensitive items** (renewals, deadlines, carry-forward blockers)

Keep this tight — 10–20 lines total. The user already knows their projects; they need the delta, not a full briefing.

## Invariants

- Always read the orientation note first.
- Never read the Raw Session Log section unless specifically investigating something.
- The core instruction file is already loaded (always-loaded); do not re-read it.
- If a session log is corrupt or has no Quick Reference section, skip it and note the skip.
- Do not present options or ask what to do — just do it and present the summary.
