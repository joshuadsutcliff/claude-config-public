---
name: grill-me
description: Use at the start of any non-trivial build, design, or research request that arrives underspecified — interrogate the user's actual intent with pointed questions BEFORE brainstorming or planning. Also invocable by name ("grill me") when the user wants their own idea stress-questioned.
---

# Grill Me

A short, aggressive requirements interrogation. The failure it prevents: building the wrong thing well. Runs BEFORE superpowers:brainstorming or any planning — brainstorming explores the solution space; this establishes the problem is real and correctly framed.

## How
1. Read the request and form a hypothesis of what the user actually wants and why.
2. Ask 2–5 pointed questions (AskUserQuestion where options are enumerable, plain text where open). Draw from:
   - **Goal**: What does done look like? What breaks or is lost if this never happens?
   - **Assumption hunt**: What is the request silently assuming? ("integrate X" — assumes X is the right tool. Is it?)
   - **Scope edge**: What's explicitly OUT? Smallest version that would still satisfy?
   - **Existing-solution check**: What's the current workaround, and what's actually wrong with it?
   - **Consequence probe**: Who/what else is affected — cost, maintenance, other machines, future-you?
3. Do NOT pad: if the request is already sharp, say so, ask at most one confirming question, and move on. The skill's value is proportional to ambiguity.
4. Restate the refined understanding in 2–3 sentences, get a nod, THEN proceed (to brainstorming, planning, or execution as appropriate).

## Rules
- Questions must be ones whose answers change what gets built. No questionnaire theater.
- Challenge respectfully but genuinely — "do you actually need this?" is a permitted question.
- One round, two max. This is a gate, not a phase.
