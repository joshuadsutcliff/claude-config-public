---
description: Create or open today's daily note in Calendar/Daily/. Structures the day with priorities, schedule (calendar MCP connector), an actionable alert ribbon (email MCP connector), and project links.
---

You are creating or opening today's daily note in your vault.

## Live-data connectors (calendar + email, optional)

This command surfaces today's **calendar** and a thin **alert ribbon** from email, using your connected calendar/email MCP tools, if configured — skip gracefully if absent.

- **Calendar** → your personal calendar account. Use `list_events` on the **primary** calendar only (do NOT pull calendars you don't own, e.g. shared/delegated calendars).
- **Email** → whichever account you've bound for this purpose (e.g. a "website/ops" inbox). Use `search_threads` for the deploy/alert slice.

**Graceful degradation (required):** the connectors are only authed on machines where the user has configured MCP. If a connector tool is unavailable or errors, **skip that section silently** (write "None." / omit the ribbon) and continue — never block note creation on a missing connector. On a fresh machine, suggest once that the user can configure MCP to enable Calendar/Email surfacing.

**Privacy (required):** persist only **curated one-liners** — event titles + times, and `sender — subject`-style alert lines. **Never** write raw email bodies into the note (use a minimal thread view; do not fetch full thread content). The daily note is committed to the private vault repo, so keep sensitive content out.

## Step 1: Determine Today's Date

Get today's date in `YYYY-MM-DD` format (use the user's local timezone). The target file is vault-relative: `Calendar/Daily/YYYY-MM-DD.md` (resolve against the current vault root — do NOT hardcode a machine path; it differs across machines).

## Step 2: Check if the Note Already Exists

**If the note exists:**
- Read it.
- Summarise what's already there: priorities, completed tasks, schedule, notes captured.
- Offer to refresh the **Schedule** and **Alerts** sections from the live connectors (re-query and update those blocks in place), and to add anything new (priorities, notes, tasks). Make requested changes and confirm.

**If the note does not exist:** proceed to create it (Steps 3–4).

## Step 3: Gather Information (for new notes)

Ask the user:
1. **Top 3 priorities** — the three most important things to accomplish today. (Wait for their answer before creating the file.)
2. Optionally: anything carrying over from yesterday?

**While waiting**, gather context in parallel:

- **Schedule (calendar connector):** call `list_events` on the primary calendar for today (`startTime` = today 00:00, `endTime` = tomorrow 00:00, your timezone, `orderBy=startTime`, `pageSize=10`). Split results into **timed events** (have a `dateTime` start → show `H:MM AM/PM — Title [@ location]`) and **all-day reminders** (have a `date` start → show as a comma-separated reminders line, e.g. Payday, Pay Rent). Ignore declined events.
- **Alerts (email connector):** call `search_threads` with a minimal thread view, a query targeting your operational senders (e.g. hosting/deploy/registrar notifications) over the last few days, `pageSize=10`. From the snippets/subjects, curate **0–3 genuinely actionable items** — deploy failures, pending repo/collaboration invites, domain/DNS/billing notices, security alerts that need action. **Exclude** transient noise (login codes, routine "new sign-in" FYIs) unless they look unauthorized. If nothing actionable, omit the ribbon.
- **Vault context:** the most recent `Areas/Work/Session-Logs/` entry's pending tasks; active projects in `Areas/Work/Projects/` (`type: project`, `status: active`).

## Step 4: Create the Daily Note

Create `Calendar/Daily/YYYY-MM-DD.md`:

```markdown
---
type: daily
date: YYYY-MM-DD
status: active
---

# YYYY-MM-DD — [Day of Week]

## Top 3 Priorities
1. [Priority 1]
2. [Priority 2]
3. [Priority 3]

## Schedule
[Timed events, one per line: "H:MM AM/PM — Title [@ location]". If none: "No timed events."]
[Reminders: all-day items as a single line, e.g. "Reminders: Payday · Pay Rent". Omit line if none.]

## Alerts
[0–3 curated actionable lines, e.g. "⚠️ Deploy failed — your-project" or "GitHub — 3 pending collab invites". Omit this whole section if nothing actionable or the connector is unavailable.]

## Active Projects
[Wikilinks to active project hubs — e.g. [[YourProjectName]]]

## Notes & Captures
[Leave blank for the user to fill in during the day]

## End of Day
- **Completed:**
- **Carrying forward:**
- **Tomorrow's focus:**
```

## Step 5: Confirm

Tell the user the file was created and where. Note which live sections populated (Schedule / Alerts) and if any connector was skipped (and why). Remind them the "End of Day" section is filled in before `/compress` at day's end.

Offer to open a specific project or run `/resume` to load full session context if they haven't.
