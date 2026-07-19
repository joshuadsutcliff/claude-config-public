# Operating Contract — Enforced Runtime

A portable Claude Code configuration that turns agent-operation *conventions* into
**executable enforcement**. Where most operating standards ask an agent to behave,
this one wires the behavior into hooks the model cannot rationalize around.

Vendor note: built for [Claude Code](https://claude.com/claude-code) (hooks + subagents).
The doctrine is portable; the enforcement mechanism is Claude Code-specific.

## Core model — Conductor / Worker

- The **main-loop model is the conductor**: it plans, judges, synthesizes, and reviews.
  "Conductor" is a *role, not a fixed model* — swap the occupant without touching the machinery.
- Token-heavy bounded work (repo/doc scans, candidate edits, test/log runs) is **delegated
  to cheaper workers** (`researcher`, `code-generator`, `tester` — see `agents/`).
- Below the paid workers sits a **free-model tier** (a bring-your-own-key harness running
  free-tier models) for self-contained second opinions, adjudications, and copy review —
  routed **usage-adaptively**: the busier the paid window, the more work shifts down, but
  never below the capability floor. Full doctrine: `docs/DELEGATION-LADDER.md`.
- Write every handoff as if the worker has zero chat context: objective, in-scope paths,
  out-of-scope surfaces, required evidence format, stop conditions.
- Treat worker reports as **leads, not facts** — re-verify cited files before acting.

## Enforcement layer (the point of this repo)

Three hooks, all **fail-open** (a broken hook must never block a prompt):

1. `hooks/usage-guard.sh` — `PreToolUse` on `Agent|Workflow`:
   - **Hard-denies** any subagent spawn that would inherit the conductor model
     (workers must be `sonnet`/`haiku`).
   - **Hard-blocks** all spawns at ≥90% of the rolling usage cap; warns at ≥70%.
   - Cap proxy = current block ÷ largest historical block (via `ccusage`), worse of tokens/cost.
2. `hooks/session-router.sh` — `UserPromptSubmit`: classifies each prompt
   **LIGHT / MEDIUM / HEAVY** (regex, no model call) and injects a tier *prior*.
   The tier is advice, not a command — the conductor overrides with judgment.
3. `SessionStart` (async) pre-warms the usage cache so later checks are instant.

> Hard limit: no hook can change the main-loop model or effort. Enforcement is
> behavioral + spawn-gating; real model-tier savings come from delegating down.

## Request flow

1. Read the tier prior injected by `session-router`.
2. LIGHT → answer directly, terse, no subagents.
   MEDIUM → delegate the heavy execution to one worker; conductor frames/judges/relays.
   HEAVY → full conductor/delegation design: plan, fan out, judge, synthesize.
3. Before spawning: confirm the worker model is `sonnet`/`haiku` (the hook enforces this).
4. End every work-completing turn with a one-line status: 🟢 done · 🟡 follow-up · 🔴 blocked.

## Memory & compounding

- Durable decisions are **preserved** (`/preserve`); sessions are **logged** (`/compress`);
  a new session **orients** first (`/resume`). See `commands/`.
- Delegation lessons accumulate in a scored playbook (helpful=N / harmful=N), evolved in
  batches — promote a lesson only when it generalizes beyond one session.

## Governance

Confirm before destructive data ops, force pushes, billing changes, external publishing,
auth changes, or permission changes. **Host project rules win on conflict.**

See `_index.md` for the full asset registry and `docs/ARCHITECTURE.md` for the layered design.
