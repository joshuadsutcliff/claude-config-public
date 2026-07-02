---
description: Process a meeting into a structured, frontmatter-tagged note saved in the correct vault location.
---

You are creating a structured meeting note in your vault.

## Step 1: Gather Meeting Details

If the user provided a transcript or notes in `$ARGUMENTS` or inline, use those as the source material.

Otherwise, ask for the following (ask all at once to minimise back-and-forth):

1. **Meeting title** — brief descriptor (e.g. "Weekly sync", "Project Alpha kickoff", "1:1 with Sarah")
2. **Date** — when did the meeting occur? (default: today, YYYY-MM-DD)
3. **Attendees** — who was in the meeting?
4. **Project** — which project does this relate to? (must match a project folder name in `Areas/Work/Projects/` exactly, or leave blank for standalone meetings)
5. **Source material** — paste any transcript, raw notes, or bullet points you have

## Step 2: Determine Save Location

- If a `project:` was given and the folder `Areas/Work/Projects/[Project-Name]/Meetings/` exists → save there
- If a `project:` was given but no project folder exists → save to `Areas/Work/Meetings/` and note that a project folder could be created
- If no project → save to `Areas/Work/Meetings/`

**File name format:** `YYYY-MM-DD-[meeting-slug].md`
Example: `2026-01-21-project-alpha-kickoff.md`

## Step 3: Process the Content

From the source material (transcript, notes, or conversation), extract:

**Summary** — 2–4 sentences covering what the meeting was about and what was resolved.

**Key Decisions** — Concrete choices that were made. Be specific. Include who made the decision if relevant.

**Action Items** — Tasks with owners and deadlines where known. Format as checkboxes.

**Discussion Points** — Important topics discussed that didn't result in a decision or task but are worth recording.

**Next Steps / Follow-up** — Any scheduled follow-ups, blockers to resolve, or open questions.

## Step 4: Create the Note

```markdown
---
type: meeting
date: YYYY-MM-DD
project: [Project-Name or omit if standalone]
attendees: [Name1, Name2, Name3]
status: completed
tags: [work]
---

# [Meeting Title] — YYYY-MM-DD

**Attendees:** Name1, Name2, Name3
**Project:** [[Project-Name]] (or omit)

## Summary
[2–4 sentences]

## Key Decisions
- [Decision — rationale if available]
- [Decision]

## Action Items
- [ ] [Task] — **Owner:** Name, **Due:** YYYY-MM-DD
- [ ] [Task] — **Owner:** Name

## Discussion Points
- [Topic discussed]
- [Topic discussed]

## Next Steps
- [Follow-up item]
- [Open question]

---
*Note created by Claude Code on [creation date]*
```

## Step 5: Confirm and Surface

After creating the file:
1. Confirm the file path
2. Remind the user that because the `project:` frontmatter is set, this meeting will automatically appear in the project hub's Dataview query — no manual linking needed
3. If any action items were captured, ask if they should also be added to today's daily note
