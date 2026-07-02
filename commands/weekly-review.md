---
description: Synthesise the week from daily notes and session logs, then create a structured weekly review in Calendar/Weekly/.
---

You are creating a weekly review for your vault.

## Step 1: Determine the Week

If `$ARGUMENTS` contains a week reference (e.g. `W04`, `last week`, a date), use that to identify the week.

Otherwise, determine the current week:
- Week number: ISO week format (e.g. W09 for the 9th week of the year)
- Week dates: Monday YYYY-MM-DD → Sunday YYYY-MM-DD
- File name: `YYYY-W##.md` (e.g. `2026-W09.md`)

Check if a review for this week already exists at `Calendar/Weekly/YYYY-W##.md`. If it does, read it and ask the user if they want to update it or create a fresh one.

## Step 2: Gather Source Material

**Daily Notes** — Read all daily notes in `Calendar/Daily/` with dates falling within the week (YYYY-MM-DD from Monday to Sunday). Extract:
- Priorities set each day
- What got completed (from End of Day sections)
- What carried forward

**Session Logs** — Read all session logs in `Areas/Work/Session-Logs/` from this week. From the Quick Reference section of each, extract:
- Topics covered
- Decisions made
- Key learnings
- Pending tasks

**Meetings** — List any notes in `Areas/Work/Meetings/` or `Areas/Work/Projects/*/Meetings/` with dates in this week.

## Step 3: Synthesise the Week

Analyse all the gathered material and identify:

**Accomplishments** — Concrete things completed or shipped. Be specific.

**Decisions Made** — Choices committed to during the week, drawn from session logs.

**Key Learnings** — Insights and discoveries worth carrying forward.

**Challenges** — Things that didn't go as planned, blockers encountered, or frustrations worth noting.

**Open Items** — Uncompleted tasks from session logs and daily notes that are still pending.

**Themes** — 2–3 word description of what this week was primarily about.

## Step 4: Create the Weekly Review

Create the file at `Calendar/Weekly/YYYY-W##.md`:

```markdown
---
type: weekly
date: YYYY-MM-DD          # Monday of the week
status: completed
tags: [review]
---

# Week YYYY-W## (Mon DD – Sun DD)

**Themes:** [Theme 1], [Theme 2]

## Accomplishments
- [Specific thing completed]
- [Specific thing completed]

## Decisions Made
- [Decision from session logs]
- [Decision]

## Key Learnings
- [Learning worth carrying forward]

## Challenges
- [Challenge or blocker encountered]

## Open Items
- [ ] [Task still pending] — from session [date]
- [ ] [Task still pending]

## Reflection
[2–4 sentences: How did the week go overall? What would you do differently? What should be the focus going into next week?]

## Next Week's Focus
1. [Top priority for next week]
2. [Second priority]
3. [Third priority]

---

### Source Material
**Daily notes reviewed:** [list of dates]
**Session logs reviewed:** [list of session log filenames]
**Meetings this week:** [count]
```

## Step 5: Surface Insights

After creating the file:

1. Present a brief spoken summary to the user: "Here's how your week looked…" followed by the top 3 accomplishments and the 2–3 open items.

2. Ask: "Any of these open items should go into next week's priorities?"

3. If there were recurring blockers or important decisions, suggest running `/preserve` to add them to CLAUDE.md.

4. If the inbox isn't empty, remind the user: "You have items in `+Inbox/` — run `/inbox-process` to clear it before starting next week."
