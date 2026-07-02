---
description: Review everything in +Inbox/, determine the correct destination for each item, add frontmatter, and file it. Leaves +Inbox/ empty.
---

You are processing your vault's inbox. The goal is to reach **inbox zero**: every item in `+Inbox/` gets a proper home in `Areas/`, `Calendar/`, or `System/`.

## Step 1: Survey the Inbox

List all files and folders in `<vault-root>/+Inbox/` (resolve against the current vault root — do not hardcode a machine path).

If the inbox is empty, tell the user and stop — nothing to do.

If there are items, read each file's content briefly to understand what it is.

## Step 2: Categorise Each Item

For each item in the inbox, determine its type and correct destination:

| What it is | Where it goes |
|---|---|
| Meeting notes or transcripts | `Areas/Work/Projects/[Project]/Meetings/` or `Areas/Work/Meetings/` |
| Project-related notes/assets | `Areas/Work/Projects/[Project]/` |
| Personal notes, goals, reflection | `Areas/Personal/` |
| Health-related content | `Areas/Health/` |
| Reusable templates | `System/Templates/` |
| Reference material for a project | `Areas/Work/Projects/[Project]/Assets/` |
| Daily note content | Merge into today's `Calendar/Daily/YYYY-MM-DD.md` |
| Unclear / needs more info | Flag for user input |

Present the proposed filing plan to the user before moving anything:

```
Inbox Processing Plan
=====================
- [filename] → Areas/Work/Projects/Project-Alpha/Meetings/ (type: meeting)
- [filename] → Areas/Personal/ (type: note)
- [filename] → UNCLEAR — needs more context (ask user)
```

Ask the user to confirm or redirect any items before proceeding.

## Step 3: Process Each Item

For each item (after user confirms the plan):

1. **Read the content**
2. **Add or update frontmatter** — every processed note needs at minimum `type:`, `date:`, and `status:`. Add `project:` if it belongs to a project.
3. **Move the file** to its destination, using the naming convention:
   - Meetings: `YYYY-MM-DD-[slug].md`
   - Notes: descriptive name, lowercase with hyphens
   - Keep original names if they're already clear
4. **Delete the original** from `+Inbox/` after the destination file is confirmed

For items flagged as UNCLEAR, ask the user directly: "What is this? Where should it go?"

## Step 4: Report

After processing all items, report:

```
Inbox Processed ✓
=================
Moved:
- [filename] → [destination]
- [filename] → [destination]

Frontmatter added to:
- [list of files that got frontmatter]

Inbox is now empty.
```

If any action items were found in inbox items, ask if they should be added to today's daily note.

If any new projects were discovered (content that references a project that doesn't have a folder yet), flag it: "I found content for '[Project-X]' but there's no project folder yet. Should I create one?"
