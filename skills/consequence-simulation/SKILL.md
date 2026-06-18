---
name: consequence-simulation
description: Use when about to commit to an irreversible or wide-blast-radius change — deploy, schema migration, data delete, config overwrite, breaking API — to surface failure modes and downstream effects before acting.
---

# Consequence Simulation

A premortem plus second-order-effects analysis: assume the plan has shipped and failed, then enumerate why; then trace the downstream 1st-, 2nd-, and 3rd-order effects of the change succeeding. Makes hidden costs and cascade risks visible before the point of no return.

## When to use
- Any irreversible action: production deploy, database migration, file deletion, force-push
- A change touches shared infrastructure or an API consumed by multiple callers
- The plan was accepted quickly and hasn't been stress-tested
- Blast radius is unclear

## Procedure
1. **State the plan** in one sentence, including the irreversibility level (reversible / costly to reverse / irreversible).
2. **Premortem** — imagine it shipped and failed catastrophically. List the top 5 failure causes ranked by likelihood × impact.
3. **First-order effects** — enumerate direct consequences of success (intended and unintended).
4. **Second-order effects** — for each first-order effect, ask "and then what?" Trace at least one chain two hops deep.
5. **Third-order / systemic effects** — what changes in behavior, incentives, or system state over time?
6. **Mitigations** — for the top 3 failure causes, propose a concrete mitigation or rollback path.
7. **Go/No-go summary** — state confidence level and any preconditions that must be true before proceeding.

## Output
A structured block: premortem list, effects tree (can be indented), mitigations table, and a final go/no-go sentence with conditions.

---
*Adapted from Compound AI Operating Standards (CC BY 4.0), Cameron Sutcliff — github.com/cameronpsutcliff/compound-ai-operating-standards.*
