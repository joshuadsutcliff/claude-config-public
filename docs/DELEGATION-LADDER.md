# The Delegation Ladder — usage-adaptive, floor-protected

*Added 2026-07-19. This extends the conductor/worker model in `AGENT.md` with a fifth,
zero-cost tier and makes the whole ladder **dynamic**: routing shifts with the live usage
signal instead of following fixed habit.*

## The ladder

| Tier | Occupant | Work it takes |
|---|---|---|
| Conductor | main-loop model | Judgment only: plan, design, adjudicate, synthesize, final review |
| Heavy worker | Opus-class (explicit opt-in) | Bounded deep reasoning: adversarial audits, gnarly debugging |
| Default worker | Sonnet-class | Grunt with tools: repo scans, TDD feature builds, test runs |
| Light worker | Haiku-class | Mechanical: log reduction, aggregation, classification |
| **Free tier** | Free-model harness (e.g. [Forge](https://forgecode.dev) with OpenRouter `:free` models **and a direct Gemini free-tier key**) | Self-contained: second opinions, adjudication cross-checks, copy/doc review, volume classification |

The free tier costs zero paid tokens. Two lanes matter for reliability: the shared
OpenRouter `:free` pool congests at peak hours (429 cascades), while a **direct
free-tier provider key** (Google AI Studio) is a *dedicated quota* immune to pool
congestion — keep it as the reserve/quality lane and default routine traffic to the
commodity pool, so the dedicated quota is charged exactly when the pool saturates.

## Usage-adaptive routing (Cascade-inspired)

Check the live burn signal (`usage-guard.sh pct`) before multi-agent work; shift the
ladder down as bands rise:

| 5-hour-window band | Posture |
|---|---|
| <50% | Normal ladder. Free tier still takes anything passing the floor — free is free. |
| 50–70% | Shift-down bias: light workers where default is marginal; free tier for every self-containable review; no speculative fan-outs. |
| 70–90% | Free-tier-first for whatever passes the floor; defer deferrable spawns; conductor narrows to the critical path. |
| ≥90% | The guard hook hard-blocks paid spawns. The free tier is the only working lane left — route what fits, pause the rest. |

Unknown signal → assume the 50–70 posture (mild shift-down is cheap insurance) and repair
the signal.

## The capability floor ("regulation, not degradation")

Never route below the floor, regardless of band:

- **Needs repo/tool/file access** → default worker or above. Free-tier models get a
  self-contained prompt *file* (include the code — they have no repo access).
- **Precision edits, multi-step agentic work, rework-cost > routing-savings** → never free tier.
- **Time-critical path** → paid tier (free-lane round trips are minutes, single-shot,
  rate-limited — no fan-outs).
- **Free-tier output is always a conductor-verified lead, never a final answer.** Empirical
  calibration from live use: free-model review reliably catches *inconsistency and
  over-claiming* (voice drift, unjustified assertions); it cannot catch *domain wrongness*
  it lacks context for. Verify in source before acting — in both directions: free-model
  dissent against a prior conclusion is sometimes right.

## Dispatch mechanics (free tier)

Write a fully self-contained prompt file → run the harness one-shot (`forge -p "$(cat
prompt.md)"` under `script` for TTY capture) → strip ANSI → take the final structured
section. Ask for narrow, plainly-formatted output — long structured answers can be mangled
by TTY column rendering; prefer re-dumping the conversation by ID over trusting a live
capture.

## Adjacent integration: spec-driven planning IDE

The same economics extend to non-CLI tools. A free-tier agentic IDE (e.g.
[Kiro](https://kiro.dev)) is seeded with **steering files** in the target repo so every
prompt lands with product context, then used for *bounded product interviews* — structured
probe prompts whose responses are captured back into the memory vault, verified against
source by a worker, and adjudicated by the conductor. The pattern generalizes: outside
opinions are cheap; verification is the conductor's job.
