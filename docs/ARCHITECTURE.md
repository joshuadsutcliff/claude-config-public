# Architecture — The Enforced Runtime

A layered design. The defining property is that the discipline is **mechanical**, not
aspirational: hooks block the failure modes rather than documenting them.

## Layer 1 — Doctrine (`AGENT.md`)

The vendor-neutral operating contract: conductor/worker roles, request flow, governance.
Read once per session; kept lean because every line is a recurring per-session token cost.

## Layer 2 — Enforcement (`hooks/`)

Where conventions become teeth. All hooks **fail open** — a broken hook exits cleanly and
never blocks a prompt.

- **`usage-guard.sh`** (`PreToolUse` on `Agent|Workflow`):
  - *Policy 1 — model floor:* unconditionally denies any subagent spawn that would inherit the
    conductor (main-loop) model. Workers must be `sonnet`/`haiku`. This cannot be rationalized
    around by the model, because it runs before the tool call executes.
  - *Policy 2 — usage gate:* computes a usage ratio (current block ÷ largest historical block,
    via `ccusage`, worse of tokens/cost) and **hard-blocks all spawns at ≥90%**, warns at ≥70%.
  - Modes: `refresh` (SessionStart cache warm), `inform` (UserPromptSubmit warning),
    `block` (the gate), `pct` (print current % for workflows to self-gate between waves).
- **`session-router.sh`** (`UserPromptSubmit`): a regex classifier (no model call) tags each
  prompt LIGHT / MEDIUM / HEAVY and injects a tier prior + policy. It is *advisory* — the tier
  is a prior, not a command. A hard harness limit means no hook can lower the main-loop
  model/effort mid-session; the router's lever is behavioral (brevity, delegation depth).

## Layer 3 — Delegation economics (`agents/`)

The conductor never does token-heavy mechanical work itself. Named workers carry it:
`researcher` (read-only evidence packets), `code-generator` (bounded diffs), `tester`
(test/log reduction). Handoffs are written for zero-context workers; reports are leads to
re-verify, not ground truth. This is what makes the model floor (Layer 2) affordable.

## Layer 4 — Bounded fan-out (`workflows/`)

`phased-review.js` is the reference for *capped* orchestration: hard ceilings (≤25 agents,
waves of 3), a usage-check between every wave (calls `usage-guard.sh pct`), and a clean halt
with resumable partial state when the cap is hit. Fan-out without these caps is the exact
failure the guard was built to prevent.

## Layer 5 — Memory & compounding (`commands/`)

- `/resume` — orient at session start from durable context + recent logs.
- `/compress` — write the session to a structured, searchable, append-only log.
- `/preserve` — route a durable decision to long-term memory so it outlives the session.
- Delegation lessons accumulate in a **scored** playbook (helpful=N / harmful=N from recorded
  outcomes, not opinion) and are promoted in batches only when they generalize.

## Layer 6 — Status convention

Every work-completing turn ends with one line, nothing after it:
🟢 finished · 🟡 non-routine follow-up remains (named) · 🔴 blocked on user input.

## Known limits (honest)

- Context-tier loading is advisory; nothing technically forces minimal loading.
- No reliable programmatic signal for a *weekly* usage cap — only the rolling-window guard is
  mechanical; the 70% warnings + small-wave discipline are the weekly protection.
- The router cannot change model/effort — only the human can, interactively.
