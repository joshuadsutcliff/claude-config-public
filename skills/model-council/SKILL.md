---
name: model-council
description: Use before committing to a high-stakes or contested decision, design, or diff — convenes 2-3 non-Claude models (via OpenRouter free tier) as independent reviewers to catch blind spots correlated across Claude-only review. Complements parallel-lens-synthesis (many lenses, one model) with many MODELS.
---

# Model Council

Cross-model peer review: fan the artifact out to 2–3 models from *different families*, each prompted as an independent skeptic, then synthesize agreement and dissent. Different training → different failure modes; this can surface what same-family lenses tend to share (advisory input, not a guarantee — models still share training-corpus blind spots). (Origin: Karpathy's llm-council + "Claude builds, Codex reviews" cross-runtime pattern.)

## When to use
- Irreversible or expensive-to-reverse decisions (architecture, migration, public API, infra change)
- A plan/finding that survived pressure-test but still feels consequential
- The user asks for a second opinion, council, or cross-model review
Skip for routine work — each convening costs council-member requests against the free-tier daily cap.

## How
1. **Frame one self-contained brief** (the council members have zero context): the decision/diff/claim, relevant constraints, and the specific question. Under ~2k words; include code inline if reviewing code.
2. **Pick 2–3 models from different families** off the current OpenRouter `:free` list (check availability, don't hardcode — the catalog churns). Prefer: one large generalist, one coder, one from a third family.
3. **Query each independently** (never share one member's answer with another before their own verdict). API key: `$OPENROUTER_API_KEY` (supply your own — never commit it anywhere). One curl per member:
   `curl -s https://openrouter.ai/api/v1/chat/completions -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{"model":"<id>","messages":[{"role":"user","content":"<skeptic prompt + brief>"}]}'`
   Skeptic prompt core: "You are an independent reviewer. Try to find what is wrong or risky in the following. Do not be agreeable; a confident 'this is sound' requires justification. End with verdict: APPROVE / APPROVE-WITH-CHANGES / REJECT + top 3 concerns."
4. **Handle free-tier reality:** 429 → try the next model on the list, don't retry-loop. Respect ~20 req/min.
5. **Synthesize as chair:** where members agree with each other (or with your own view), note it briefly; where they dissent, dig into WHY before dismissing — dissent from a weaker model can still mark a real blind spot. Deliver: consensus, live disagreements, your final recommendation, and what changed because of the council.

## Rules
- Council output is advisory input to YOUR judgment, not a vote you're bound by.
- Never send secrets, credentials, or private identifying data in the brief — these are third-party models.
- If no external models are reachable, say so and fall back to parallel-lens-synthesis; never fake a council.
