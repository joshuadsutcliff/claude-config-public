# Obsidian + Claude Code Integration Guide

**Audience:** a Claude Code instance, pointed at this repo by a user who said something like
"integrate this into my setup." Read this whole file before touching the user's files, then
work through **Integration Steps** below, checking in with the user where marked.

## Overview

This repo pairs a Claude Code configuration with an **Obsidian vault used as a long-term memory
backend**. The vault is not just notes — it's the durable store that makes an agent's context
compound across sessions instead of resetting every time. The workflow has three layers:

- **Capture** — quick, low-friction notes land in a single inbox folder (`+Inbox/`), not filed
  correctly yet.
- **Process** — captured items get frontmatter (`type`, `date`, `status`, …) and move to their
  proper home under `Areas/`, `Calendar/`, or `System/`.
- **Surface** — nothing is manually linked. Frontmatter-driven Dataview queries in project hubs,
  dashboards, and index notes pull matching notes in automatically. This is the "**Write Once,
  Surface Everywhere**" principle: add frontmatter once, and the note appears in every relevant
  view without hand-wiring links.

Each session follows a fixed bracket: **`/resume`** opens it (load orientation + recent session
logs), work happens, **`/wrap`** closes it (preserve durable decisions, write a session log,
sync config if needed). This is what lets a new session start with real continuity instead of a
blank slate.

## Command / skill reference

| Name | What it does | When it runs |
|---|---|---|
| `/resume` | Loads orientation note + recent session logs; presents a tight status summary. | Start of every session. |
| `/wrap` | Orchestrates preserve-check → `/compress` → `/sync-config` in the correct order. | End of every session. |
| `/compress` | Writes the session as a structured, searchable, append-only log; commits/pushes the vault. | Called by `/wrap`, or standalone. |
| `/preserve` | Routes a durable decision/learning to CLAUDE.md core, a depth note, or an archive. | Called by `/wrap`, or standalone when something durable comes up mid-session. |
| `/daily-note` | Creates/opens today's daily note: priorities, schedule, an alert ribbon, project links. | Start of day, or on demand. |
| `/inbox-process` | Files everything in `+Inbox/` to its correct destination with frontmatter added. | Daily/periodically, whenever the inbox has items. |
| `/meeting-note` | Turns a transcript/notes into a structured, frontmatter-tagged meeting note. | After any meeting worth recording. |
| `/new-project` | Scaffolds a project folder (hub note + `Assets/` + `Meetings/`) and registers it in CLAUDE.md. | Starting a new project. |
| `/weekly-review` | Synthesizes the week from daily notes + session logs into a structured review. | End of week. |
| `/goal` | Runs a task under a Goal Contract (+ Loop Spec if recurring), gated by the usage proxy. | Any long-running or looping task. |
| `/sync-config` | Reconciles `~/.claude` config with your shared config repo (two-way). | Whenever config drifted; called by `/wrap`. |
| `/sync-machine` | One-time onboarding of a new machine into vault + config git mirroring. | Once, per new machine. |
| `usage-guard.sh` (hook) | Blocks subagent spawns that would inherit the main-loop model; hard-blocks near the usage cap; warns earlier. | `PreToolUse`, `UserPromptSubmit`, `SessionStart`. |
| `session-router.sh` (hook) | Classifies each prompt LIGHT/MEDIUM/HEAVY and injects a tier prior. | `UserPromptSubmit`. |
| `post-compact.sh` (hook) | Re-grounds the model after auto-compaction wipes live working state. | `SessionStart` (only fires on `source == "compact"`). |
| `efficient-fable` (skill) | Conductor/worker delegation design for token-heavy work. | Auto-invoked; vendored/managed upstream. |
| `quick-recap` (skill) | The 🟢/🟡/🔴 end-of-response status-line convention. | Auto-invoked; vendored/managed upstream. |
| `stay-within-limits` (skill) | Usage-aware pausing across long/parallel work. | Auto-invoked; vendored/managed upstream. |
| `code-reviewer` (agent) | Reviews a completed project step against its plan + coding standards. | Invoke after finishing a planned chunk of work. |
| `researcher` / `code-generator` / `tester` (agents) | Bounded delegation workers (read-only scans / patches / test runs). | Delegated to by the conductor for token-heavy bounded work. |
| `templates/CLAUDE.vault.example.md` | Fill-in-the-blanks starting point for a vault-level CLAUDE.md. | Once, when first integrating. |

## Integration Steps

Work through these in order. Ask the user for input at every step marked **ASK**.

### (a) Copy the assets into `~/.claude/`

```bash
mkdir -p ~/.claude/commands ~/.claude/skills ~/.claude/agents ~/.claude/hooks
cp commands/*.md ~/.claude/commands/
cp -R skills/* ~/.claude/skills/
cp agents/*.md ~/.claude/agents/
cp hooks/*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
```

Don't blindly overwrite files the user already has with the same name — diff first and ask
before replacing anything non-trivial.

### (b) Wire the hooks into settings.json

Read `settings.example.json` in this repo and merge its `hooks` block (and `effortLevel` if
desired) into the user's `~/.claude/settings.json` — don't just copy the file wholesale if they
already have one; merge so existing keys survive. If they also copied `post-compact.sh`, add it
under `SessionStart` (synchronous, so its `additionalContext` reaches the model) alongside the
existing `usage-guard.sh refresh` entry.

**Tell the user explicitly: hooks and `settings.json` are only read at session start.** They
take effect on the *next* new Claude Code session, not the current one.

### (c) Create the vault folder skeleton

If the user doesn't already have a vault, ask where it should live (**ASK**), then check for and
create anything missing:

```bash
mkdir -p "<vault-root>/+Inbox"
mkdir -p "<vault-root>/Areas/Work/Session-Logs"
mkdir -p "<vault-root>/Areas/Work/Projects"
mkdir -p "<vault-root>/Calendar/Daily" "<vault-root>/Calendar/Weekly" "<vault-root>/Calendar/Monthly"
mkdir -p "<vault-root>/System/Templates" "<vault-root>/System/Dashboards" "<vault-root>/System/References"
```

Only create what's missing — never clobber an existing folder's contents.

### (d) Create or extend the vault's CLAUDE.md

Read `templates/CLAUDE.vault.example.md` from this repo. If the vault has no `CLAUDE.md`, copy
it in as a starting point. If one already exists, **do not overwrite it** — instead merge in
whichever sections are missing (Folder Structure, Frontmatter Standards, Conventions, Memory Map)
and leave everything else the user already wrote untouched.

### (e) Replace every placeholder

Search the newly-copied commands and the new CLAUDE.md for `<vault-root>`, `<your-username>`,
`<your-*-repo>`, `your-*-hostname`, and similar bracketed placeholders. For each one, **ASK the
user for the real value** rather than guessing — vault path, GitHub username, repo names,
per-machine hostnames, calendar/email accounts to bind (if using `/daily-note`). Do a global
find-and-replace only after confirming each value.

### (f) Verify with a dry run

Tell the user to start a **new** Claude Code session (so the hooks/settings take effect), then
run `/resume`. It should report "no session logs yet" gracefully rather than erroring — that
confirms the folder skeleton and command wiring are correct. Fix anything that errors before
declaring the integration done.

## Adapt, don't assume

Not every piece here is required. Ask the user what they actually want before installing all of
it:

- **Multi-machine sync** (`/sync-machine`, `/sync-config`) — only relevant if the user runs
  Claude Code on more than one machine and wants the vault + config mirrored via git. Skip
  entirely for a single-machine setup.
- **`usage-guard.sh`** — needs the `ccusage` CLI installed and on `PATH` to compute the usage
  ratio; it fails open (never blocks) if `ccusage` is missing, but it also won't do anything
  useful without it. Ask if the user wants usage-cap enforcement before wiring it in.
- **`session-router.sh`** — a pure regex classifier with no external dependency, safe to install
  by default, but purely advisory — skip if the user doesn't want prompt-tier framing injected
  into context.
- **`post-compact.sh`** — only useful if the user's sessions run long enough to hit
  auto-compaction; harmless otherwise (it's a no-op except right after a compaction event).
- **Calendar/email MCP connectors for `/daily-note`** — entirely optional; the command degrades
  gracefully (skips the Schedule/Alerts sections) if no connector is configured.
- **`efficient-fable` / `quick-recap` / `stay-within-limits`** — vendored copies of
  upstream-managed skills. If the user's Claude Code install already provides these (e.g. via a
  plugin), prefer the upstream version over this vendored copy to avoid drift.
