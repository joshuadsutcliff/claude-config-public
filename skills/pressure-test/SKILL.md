---
name: pressure-test
description: Use when validating a finding, plan, design, or proposed change before acting on it — especially after a subagent report, a confident recommendation, or any claim that will drive an irreversible decision.
---

# Pressure Test

Adversarial critique of a proposal, claim, or design across a fixed set of lenses. Treats the input as a defendant and attempts to break it, rather than extend it. Produces a ranked list of vulnerabilities and a survivability verdict.

## When to use
- A subagent or tool returned a finding you're about to act on
- A design or plan passed initial review and feels ready to ship
- A claim is being used to justify a significant investment of time or resources
- You want independent adversarial coverage before committing

## Procedure
1. **Restate the claim/design** in one sentence. Confirm you understand what is being pressure-tested.
2. **Apply each lens** in turn — write a critique or "no issue found" for each:
   - **Correctness** — is the logic sound? Are there edge cases that break it?
   - **Security** — what attack surfaces, injection points, or trust assumptions exist?
   - **Performance** — does it degrade under load, scale badly, or have hidden O(n²) paths?
   - **Maintainability** — is it legible, testable, and safe to change in 6 months?
   - **Failure modes** — what happens when dependencies are unavailable, inputs are malformed, or state is inconsistent?
   - **Hidden assumptions** — what must be true for this to work that is not stated or verified?
3. **Rank findings** by severity (critical / high / medium / low). Drop anything that is purely cosmetic.
4. **Survivability verdict** — state whether the proposal survives pressure testing as-is, survives with mitigations, or fails.

## Output
A table or labeled list of findings per lens with severity tags, followed by a one-paragraph verdict and recommended next action.

---
*Adapted from Compound AI Operating Standards (CC BY 4.0), Cameron Sutcliff — github.com/cameronpsutcliff/compound-ai-operating-standards.*
