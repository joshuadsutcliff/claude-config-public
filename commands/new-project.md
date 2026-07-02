---
description: Scaffold a new project folder with hub note, Assets/ and Meetings/ subfolders, and Dataview queries. Registers the project in CLAUDE.md.
---

You are creating a new project in your vault.

## Step 1: Gather Project Details

If the user provided a project name in `$ARGUMENTS`, use that. Otherwise ask:

1. **Project name** — used as the folder name. Must be PascalCase with hyphens (e.g. `Project-Alpha`, `Client-Website`, `Side-Project`). No spaces.
2. **Project description** — one sentence about what this project is
3. **Status** — `active` (default) or `on-hold`
4. **Tags** — optional (e.g. `[work, client]` or `[personal]`)
5. **Start date** — default: today (YYYY-MM-DD)

## Step 2: Validate the Name

Check that a folder does not already exist at:
`Areas/Work/Projects/[Project-Name]/`

If it exists, stop and tell the user.

## Step 3: Create the Folder Structure

Create these paths:
- `Areas/Work/Projects/[Project-Name]/` (the project root)
- `Areas/Work/Projects/[Project-Name]/Assets/` (files, exports, screenshots)
- `Areas/Work/Projects/[Project-Name]/Meetings/` (meeting notes for this project)

## Step 4: Create the Project Hub Note

Create `Areas/Work/Projects/[Project-Name]/[Project-Name].md`:

```markdown
---
type: project
date: YYYY-MM-DD
project: Project-Name
status: active
tags: [work]
---

# Project-Name

## Overview
[Project description]

## Goals
-

## Key Links & Resources
-

---

## Meetings

\`\`\`dataview
TABLE date, attendees, status
FROM "Areas/Work/Projects/Project-Name/Meetings"
WHERE type = "meeting"
SORT date DESC
\`\`\`

---

## Session Logs

\`\`\`dataview
TABLE date, topics
FROM "Areas/Work/Session-Logs"
WHERE type = "session" AND project = "Project-Name"
SORT date DESC
LIMIT 10
\`\`\`

---

## Open Tasks

\`\`\`dataview
TASK
FROM "Areas/Work/Projects/Project-Name"
WHERE !completed
SORT file.mtime DESC
\`\`\`
```

## Step 5: Register in CLAUDE.md

Read `<vault-root>/CLAUDE.md` (resolve against the current vault root) and add the new project under the **Active Projects** section:

```
- **[Project-Name]** — [description] (status: active, started: YYYY-MM-DD)
```

## Step 6: Confirm

Tell the user:
- The folder structure created
- The hub note path
- That it's now registered in CLAUDE.md and will appear in the Work Index automatically
- Suggest running `/daily-note` if they want to set today's priorities for this new project
