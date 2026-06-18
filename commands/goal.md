# /goal — Run a task under a Goal Contract (and Loop Spec if it loops)

Wrap a substantial, multi-step task in a verifiable contract before doing the work. For
recurring/self-prompting runs, also write a Loop Spec — no loop runs without one. Full doctrine:
`docs/goal-loop-engineering.md`.

## Step 1 — Write the Goal Contract

Fill all six fields. Reject vague completion conditions.

```
GOAL CONTRACT
Objective:            <what should be true when done>
Completion condition: <observable, checkable by a SEPARATE evaluator — not "looks done">
Validation:           <exact commands / rendered checks / review gate / source evidence>
Context budget:       <what to load now vs. keep as pointers>
Stop conditions:      <met+validated | destructive-without-approval | no-access | ambiguous | budget-exhausted>
Memory update:        <what log / decision / pattern note closes the loop>
```

## Step 2 — If the task loops, add a Loop Spec (3 hard stops required)

```
LOOP SPEC
Max iterations:   <N — hard halt>
No-progress rule: halt after 2 consecutive no-op / repeated-rejected iterations
Budget ceiling:   <usage % — checked via the usage-guard `pct` mode before each iteration>
Verification:     <checker ≠ maker — delegate to a worker or a command>
Autonomy ceiling: <scope + reversibility/blast radius>
Open or closed:   closed (default) | open (requires explicit operator go)
```

## Step 3 — Run

1. Before each iteration: run the usage-guard `pct` mode (`~/.claude/hooks/usage-guard.sh pct`)
   → if ≥ ceiling, **halt + record state**.
2. Do ONE bounded iteration; delegate token-heavy work to a cheaper worker.
3. Run the delegated verification; update a progress counter.
4. On any hard stop → write closure state and STOP.
5. On completion → run the Memory-update field; promote the lesson if it generalizes.

## Invariants

- The maker never grades its own completion — verification is delegated or command-based.
- A loop missing any of the three hard stops does not run.
- Budget ceiling uses the SAME usage proxy as the spawn-gate, so they agree on one number.
