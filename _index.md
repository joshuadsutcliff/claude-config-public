# Asset Index

Registry of every tracked asset. Entry point: `AGENT.md`. Design: `docs/ARCHITECTURE.md`.

## Hooks (`hooks/`) — the enforcement layer

| Hook | Event | Function |
|---|---|---|
| `usage-guard.sh` | `PreToolUse` (Agent\|Workflow), `UserPromptSubmit`, `SessionStart` | 4 modes: `refresh` (warm cache), `inform` (≥70% warn), `block` (deny conductor-model spawns; hard-block ≥90% cap), `pct` (print current usage %). |
| `session-router.sh` | `UserPromptSubmit` | Classifies prompt LIGHT/MEDIUM/HEAVY via regex; injects a tier prior + policy into context. No model call. |
| `post-compact.sh` | `SessionStart` | Fires only when `source == "compact"`; re-injects a re-grounding instruction (restate objective, re-read active plan + latest session log, re-confirm pending tasks) after auto-compaction wipes live working state. Fail-open; disable with `POST_COMPACT_OFF=1`. |

## Workers (`agents/`) — delegation targets

| Worker | Model | Role |
|---|---|---|
| `researcher` | sonnet (low) | Read-only scans → structured evidence packet. Never edits. |
| `code-generator` | sonnet | Bounded edits/patches/refactors → diff-centric report. |
| `tester` | haiku | Test runs + log reduction → findings classified real/flaky/environmental. |
| `code-reviewer` | sonnet | Reviews a completed project step against its original plan + coding standards; categorizes issues Critical/Important/Suggestion. |

## Commands (`commands/`) — session lifecycle

| Command | Function |
|---|---|
| `/resume` | Orient at session start: load the operating context + recent session logs. |
| `/wrap` | Unified session close: preserve-check → `/compress` → `/sync-config`, skipping steps that aren't needed. |
| `/compress` | Save the session as a structured, searchable log. |
| `/preserve` | Route a durable decision/learning to the right long-term home. |
| `/goal` | Run a task under a Goal Contract (+ Loop Spec if it loops); stops wired to the usage proxy. See `docs/goal-loop-engineering.md`. |

## Commands (`commands/`) — vault workflow (Obsidian)

See `docs/OBSIDIAN-SETUP.md` for the full integration guide.

| Command | Function |
|---|---|
| `/sync-config` | Two-way reconcile of `~/.claude` config with the shared config repo. |
| `/sync-machine` | One-time onboarding of a new machine into vault + config git mirroring. |
| `/daily-note` | Create/open today's daily note: priorities, schedule, alert ribbon, project links. Calendar/email connectors are optional and degrade gracefully. |
| `/inbox-process` | File everything in `+Inbox/` to its correct destination with frontmatter added. |
| `/meeting-note` | Turn a transcript/notes into a structured, frontmatter-tagged meeting note. |
| `/new-project` | Scaffold a project folder (hub note + `Assets/` + `Meetings/`) and register it in CLAUDE.md. |
| `/weekly-review` | Synthesize the week from daily notes + session logs into a structured review. |

## Skills (`skills/`) — hand-authored cognitive techniques

Auto-invoked by their `description`. Adapted from Compound AI Operating Standards (CC BY 4.0).

| Skill | Use when |
|---|---|
| `parallel-lens-synthesis` | A decision is high-stakes/contested; stress-test before committing. |
| `consequence-simulation` | Before an irreversible / wide-blast-radius change (premortem + 2nd-order effects). |
| `detached-judgment` | Countering sycophancy/anchoring; evidence is thin but the pull to validate is strong. |
| `pressure-test` | Validating a finding/plan/design across fixed adversarial lenses before acting. |
| `nod-protocol` | "Negate Own Default" — stress a fast, confident conclusion before locking it in. |

## Skills (`skills/`) — vendored from upstream

Copied in full (including assets) from the upstream Claude Code skills distribution; each
README carries a provenance comment. May be updated upstream — check for drift periodically.

| Skill | Use when |
|---|---|
| `efficient-fable` | Orchestrating codebase-heavy work with a Fable-class conductor delegating to cheaper subagents. |
| `quick-recap` | Installing/following the 🟢/🟡/🔴 end-of-response status-line convention. |
| `stay-within-limits` | Long-running or parallel work needs to respect 5-hour/weekly usage limits. |

## Workflows (`workflows/`)

| Workflow | Function |
|---|---|
| `phased-review.js` | Spec-drift review: contract → baseline → parallel audits → adversarial verify → ranked report. Usage-gated, wave-capped (≤25 agents, waves of 3), all subagents on sonnet/haiku. |

## Config

| File | Function |
|---|---|
| `settings.example.json` | Shared hook wiring + `effortLevel` baseline. Copy to `settings.json`; keep machine-specific values in a gitignored `settings.local.json`. |

## Templates (`templates/`)

| File | Function |
|---|---|
| `CLAUDE.vault.example.md` | Fill-in-the-blanks starting point for a vault-level CLAUDE.md: Environment, Vault Identity, Folder Structure (Capture/Process/Surface), Frontmatter Standards, Conventions, Memory Map, Active Projects. |

## Docs (`docs/`)

| File | Function |
|---|---|
| `ARCHITECTURE.md` | The layered design of the enforcement runtime. |
| `goal-loop-engineering.md` | Goal Contracts + Loop Specs wired to the usage proxy. |
| `OBSIDIAN-SETUP.md` | Claude-facing integration guide: what the vault workflow is, the command/skill reference, and step-by-step instructions for wiring it into a new setup. |

## Not included here

The hand-authored cognitive skills and the three vendored skills above **are** included. Only
`visual-plan` and `visual-recap` (installed via the plugin system, overwritten on update) are
referenced, not vendored — see `README.md` → "Skills".
