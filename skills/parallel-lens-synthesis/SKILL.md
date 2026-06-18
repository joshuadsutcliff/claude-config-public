---
name: parallel-lens-synthesis
description: Use when a decision is high-stakes or contested, a single framing risks tunnel vision, or you need to stress-test a recommendation before committing to it.
---

# Parallel Lens Synthesis

Generate multiple independent framings of a problem — each developed in isolation so they do not contaminate each other — then synthesize a position that accounts for all of them. Prevents tunnel vision and surfaces blind spots that a single-perspective analysis will miss.

## When to use
- A design, architectural, or strategic decision has meaningful trade-offs
- The user is advocating strongly for one option (anchoring risk)
- The problem involves multiple stakeholders with conflicting interests
- You caught yourself converging on an answer faster than the complexity warrants

## Procedure
1. **Name the lenses** relevant to this problem (default set: user/UX, risk, cost/effort, maintainer, security; add domain-specific lenses as needed).
2. **Develop each lens independently** — write a short paragraph for each without referencing the others. Stop before synthesis.
3. **Steelman the leading option** — state its strongest possible case.
4. **Red-team the leading option** — state the strongest case against it.
5. **Synthesize** — identify the 2-3 tensions that matter most, state how they resolve (or don't), and produce a recommendation with explicit caveats.
6. **Flag residuals** — note any lens where the evidence was too thin to draw a conclusion.

## Output
A structured response with one labeled section per lens, a steelman block, a red-team block, and a synthesis conclusion. End with a one-line verdict and open questions if any remain.

---
*Adapted from Compound AI Operating Standards (CC BY 4.0), Cameron Sutcliff — github.com/cameronpsutcliff/compound-ai-operating-standards.*
