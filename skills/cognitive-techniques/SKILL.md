---
name: cognitive-techniques
description: >-
  Use when stress-testing a decision, plan, claim, or requirement before
  committing, or when a request arrives underspecified. Covers: multi-lens
  analysis for high-stakes decisions (parallel lenses); adversarial critique
  of a finding or plan (pressure-test); negating your own default conclusion
  to catch overconfidence (NOD); surfacing failure modes before irreversible
  actions like deploys or migrations (consequence simulation); interrogating
  underspecified requirements with pointed questions before planning or
  building (grill-me).
---

# Cognitive Techniques

Merged 2026-07-21 from five standalone skills; pick the technique matching the situation.

## Parallel-Lens Synthesis

Generate multiple independent framings of a problem — each developed in isolation so they do not contaminate each other — then synthesize a position that accounts for all of them. Prevents tunnel vision and surfaces blind spots that a single-perspective analysis will miss.

**When to use**
- A design, architectural, or strategic decision has meaningful trade-offs
- The user is advocating strongly for one option (anchoring risk)
- The problem involves multiple stakeholders with conflicting interests
- You caught yourself converging on an answer faster than the complexity warrants

**Procedure**
1. **Name the lenses** relevant to this problem (default set: user/UX, risk, cost/effort, maintainer, security; add domain-specific lenses as needed).
2. **Develop each lens independently** — write a short paragraph for each without referencing the others. Stop before synthesis.
3. **Steelman the leading option** — state its strongest possible case.
4. **Red-team the leading option** — state the strongest case against it.
5. **Synthesize** — identify the 2-3 tensions that matter most, state how they resolve (or don't), and produce a recommendation with explicit caveats.
6. **Flag residuals** — note any lens where the evidence was too thin to draw a conclusion.

**Output**: A structured response with one labeled section per lens, a steelman block, a red-team block, and a synthesis conclusion. End with a one-line verdict and open questions if any remain.

## Pressure-Test

Adversarial critique of a proposal, claim, or design across a fixed set of lenses. Treats the input as a defendant and attempts to break it, rather than extend it. Produces a ranked list of vulnerabilities and a survivability verdict.

**When to use**
- A subagent or tool returned a finding you're about to act on
- A design or plan passed initial review and feels ready to ship
- A claim is being used to justify a significant investment of time or resources
- You want independent adversarial coverage before committing

**Procedure**
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
- **Concurrency gates must be race-tested with truly concurrent invocations in a sandbox** (e.g. two backgrounded invocations against a HOME-sandboxed copy) — one passing live interleaving is NOT evidence a gate serializes; the harness may have serialized for you (2026-07-21 gh-mutex TOCTOU).

**Output**: A table or labeled list of findings per lens with severity tags, followed by a one-paragraph verdict and recommended next action.

## NOD Protocol (Negate Own Default)

Construct the strongest possible case against your current position or recommendation, then decide whether it survives. Designed to catch the failure mode where a model converges confidently on an answer that feels right but hasn't been genuinely challenged. NOD = Negate Own Default.

**When to use**
- You reached a conclusion fast and feel high confidence
- The user accepted your recommendation without pushback and you're about to act
- The problem is novel or outside your well-calibrated domain
- You are about to take an action that is hard to reverse

**Procedure**
1. **State the default** — write your current recommendation or conclusion in one sentence.
2. **Steelman the opposition** — build the single strongest argument against your default. Use the best evidence, analogies, and logic available. Do not strawman. Treat this as if you are a skilled adversary trying to defeat your own position.
3. **Identify the crux** — what is the single factual or logical claim your default depends on most? If that claim is wrong, does the default collapse?
4. **Probe the crux** — how confident are you in it? What would falsify it? Is there evidence you haven't checked?
5. **Re-evaluate** — after the steelman and crux probe, does your default still hold? Options: (a) default survives — state why the steelman fails; (b) default weakens — revise it; (c) default collapses — adopt the opposition.
6. **Lock or revise** — state the final position explicitly. If locking, include the condition that would change it.

**Output**: A structured block with each step labeled. The final locked or revised position must be a single unambiguous sentence. Do not hedge into vagueness to avoid commitment.

## Consequence Simulation

A premortem plus second-order-effects analysis: assume the plan has shipped and failed, then enumerate why; then trace the downstream 1st-, 2nd-, and 3rd-order effects of the change succeeding. Makes hidden costs and cascade risks visible before the point of no return.

**When to use**
- Any irreversible action: production deploy, database migration, file deletion, force-push
- A change touches shared infrastructure or an API consumed by multiple callers
- The plan was accepted quickly and hasn't been stress-tested
- Blast radius is unclear

**Procedure**
1. **State the plan** in one sentence, including the irreversibility level (reversible / costly to reverse / irreversible).
2. **Premortem** — imagine it shipped and failed catastrophically. List the top 5 failure causes ranked by likelihood × impact.
3. **First-order effects** — enumerate direct consequences of success (intended and unintended).
4. **Second-order effects** — for each first-order effect, ask "and then what?" Trace at least one chain two hops deep.
5. **Third-order / systemic effects** — what changes in behavior, incentives, or system state over time?
6. **Mitigations** — for the top 3 failure causes, propose a concrete mitigation or rollback path.
7. **Go/No-go summary** — state confidence level and any preconditions that must be true before proceeding.

**Output**: A structured block: premortem list, effects tree (can be indented), mitigations table, and a final go/no-go sentence with conditions.

## Grill-Me

A short, aggressive requirements interrogation. The failure it prevents: building the wrong thing well. Runs BEFORE superpowers:brainstorming or any planning — brainstorming explores the solution space; this establishes the problem is real and correctly framed. Also invocable by name ("grill me") when the user wants their own idea stress-questioned.

**How**
1. Read the request and form a hypothesis of what the user actually wants and why.
2. Ask 2–5 pointed questions (AskUserQuestion where options are enumerable, plain text where open). Draw from:
   - **Goal**: What does done look like? What breaks or is lost if this never happens?
   - **Assumption hunt**: What is the request silently assuming? ("integrate X" — assumes X is the right tool. Is it?)
   - **Scope edge**: What's explicitly OUT? Smallest version that would still satisfy?
   - **Existing-solution check**: What's the current workaround, and what's actually wrong with it?
   - **Consequence probe**: Who/what else is affected — cost, maintenance, other machines, future-you?
3. Do NOT pad: if the request is already sharp, say so, ask at most one confirming question, and move on. The skill's value is proportional to ambiguity.
4. Restate the refined understanding in 2–3 sentences, get a nod, THEN proceed (to brainstorming, planning, or execution as appropriate).

**Rules**
- Questions must be ones whose answers change what gets built. No questionnaire theater.
- Challenge respectfully but genuinely — "do you actually need this?" is a permitted question.
- One round, two max. This is a gate, not a phase.

---
*Adapted from Compound AI Operating Standards (CC BY 4.0): github.com/cameronpsutcliff/compound-ai-operating-standards.*
