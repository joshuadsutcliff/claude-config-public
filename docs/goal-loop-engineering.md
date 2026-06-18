# Goal & Loop Engineering

Adapts the **Goal Contract** and **Loop Spec** discipline from [Compound AI Operating
Standards](https://github.com/cameronpsutcliff/compound-ai-operating-standards) (CC BY 4.0,
Cameron Sutcliff) onto this enforced-runtime config — with the key blend: a loop's **budget
ceiling** and **no-progress halt** are wired to the *real* usage proxy (`usage-guard.sh pct`),
not left as prose the agent is trusted to honor. Invoke via the `/goal` command.

## When to use

- Any **substantial, multi-step task with a verifiable finish line** → wrap it in a Goal Contract.
- Any **recurring or self-prompting run** (e.g. a `/loop`) → it **must** have a Loop Spec first.
  *No loop runs without a spec — an unspecced loop is an incident scheduled for later.*
- Skip for one-shot conversational turns and trivial edits.

## Goal Contract (6 fields)

| Field | Meaning |
|---|---|
| **Objective** | What should be true when the work is done. |
| **Completion condition** | An *observable* condition a **separate evaluator** can check — not "looks done." Code: tests/lint/build/smoke pass. Docs: rendered + links resolve. Vague conditions are rejected. |
| **Validation** | The exact commands / checks / review gates / source evidence used to confirm it. The checker is **not** the maker. |
| **Context budget** | What to load now vs. keep as pointers. |
| **Stop conditions** | Halt only when: condition met + validated · destructive-without-approval · no access · genuinely ambiguous · budget exhausted (record progress first). |
| **Memory update** | What log/decision/pattern updates close the loop. |

## Loop Spec — three HARD stops (required) + governance

A loop missing any of the three hard stops does not run.

1. **Max iterations** — hard halt at N.
2. **No-progress rule** — halt after **2** consecutive no-op / repeated-rejected iterations.
3. **Budget ceiling** — tokens / time / iterations / usage-%. **Wired to the usage proxy** (below).

Governance fields: **Verification (checker ≠ maker)** · **Memory file** (read first, write last) ·
**Escalation target** · **Autonomy ceiling** (scope + blast radius) · **Open or closed**
(closed by default; an open loop acting without per-iteration approval needs explicit operator go).

## The blend — wiring stops to real enforcement

Hooks **cannot** intercept individual loop iterations (the PreToolUse guard only gates
`Agent`/`Workflow` spawns). So loop-stop enforcement is **driven by the agent**, using the
guard as the source of truth:

- **Budget ceiling → `usage-guard.sh pct`.** Before each iteration, run the guard's `pct` mode
  (`hooks/usage-guard.sh pct`, or `~/.claude/hooks/usage-guard.sh pct` when installed). If it
  returns `≥` the spec's ceiling (default: the guard's own block threshold), **halt and record
  state**. The loop and the spawn-gate then agree on one usage number.
- **No-progress → an explicit counter.** Track a progress signal per iteration; two no-ops → halt.
- **Verification → a delegated checker.** The completion condition is validated by a separate
  worker or a command, never by the agent that did the work.

---

*Adapted from Compound AI Operating Standards (CC BY 4.0), Cameron Sutcliff.*
