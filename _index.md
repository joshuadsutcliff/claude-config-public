# Asset Index

Registry of every tracked asset. Entry point: `AGENT.md`. Design: `docs/ARCHITECTURE.md`.

## Hooks (`hooks/`) — the enforcement layer

| Hook | Event | Function |
|---|---|---|
| `usage-guard.sh` | `PreToolUse` (Agent\|Workflow), `UserPromptSubmit`, `SessionStart` | 4 modes: `refresh` (warm cache), `inform` (≥70% warn), `block` (deny conductor-model spawns; hard-block ≥90% cap), `pct` (print current usage %). |
| `session-router.sh` | `UserPromptSubmit` | Classifies prompt LIGHT/MEDIUM/HEAVY via regex; injects a tier prior + policy into context. No model call. |

## Workers (`agents/`) — delegation targets

| Worker | Model | Role |
|---|---|---|
| `researcher` | sonnet (low) | Read-only scans → structured evidence packet. Never edits. |
| `code-generator` | sonnet | Bounded edits/patches/refactors → diff-centric report. |
| `tester` | haiku | Test runs + log reduction → findings classified real/flaky/environmental. |

## Commands (`commands/`) — session lifecycle

| Command | Function |
|---|---|
| `/resume` | Orient at session start: load the operating context + recent session logs. |
| `/compress` | Save the session as a structured, searchable log. |
| `/preserve` | Route a durable decision/learning to the right long-term home. |
| `/goal` | Run a task under a Goal Contract (+ Loop Spec if it loops); stops wired to the usage proxy. See `docs/goal-loop-engineering.md`. |

## Skills (`skills/`) — hand-authored cognitive techniques

Auto-invoked by their `description`. Adapted from Compound AI Operating Standards (CC BY 4.0).

| Skill | Use when |
|---|---|
| `parallel-lens-synthesis` | A decision is high-stakes/contested; stress-test before committing. |
| `consequence-simulation` | Before an irreversible / wide-blast-radius change (premortem + 2nd-order effects). |
| `detached-judgment` | Countering sycophancy/anchoring; evidence is thin but the pull to validate is strong. |
| `pressure-test` | Validating a finding/plan/design across fixed adversarial lenses before acting. |
| `nod-protocol` | "Negate Own Default" — stress a fast, confident conclusion before locking it in. |

## Workflows (`workflows/`)

| Workflow | Function |
|---|---|
| `phased-review.js` | Spec-drift review: contract → baseline → parallel audits → adversarial verify → ranked report. Usage-gated, wave-capped (≤25 agents, waves of 3), all subagents on sonnet/haiku. |

## Config

| File | Function |
|---|---|
| `settings.example.json` | Shared hook wiring + `effortLevel` baseline. Copy to `settings.json`; keep machine-specific values in a gitignored `settings.local.json`. |

## Not included here

The hand-authored cognitive skills above **are** included. Only the **vendored/managed** skills
(installed via the plugin system, overwritten on update — e.g. `efficient-fable`, `quick-recap`,
`stay-within-limits`, `visual-plan`, `visual-recap`) are referenced, not vendored — see
`README.md` → "Skills".
