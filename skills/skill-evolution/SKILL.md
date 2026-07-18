---
name: skill-evolution
description: Use when noticing friction with any skill mid-session (ignored rules, missing coverage, over-complexity), when the user corrects how their intent was read, and during /wrap — logs observations to the observation file; runs an evolution pass when ≥5 are unprocessed. The skills-and-user-model improvement loop.
---

# Skill Evolution

Continuous improvement loop for the skill library AND for the model of the user. Observations accumulate cheaply during real work; changes are applied in deliberate, human-reviewed passes. Generalizes the Fable-Delegation-Playbook ACE pass to everything.

**Observation log:** `~/.claude/skills/skill-evolution/observations.md` (append-only entries; created on first use; **local/private — keep it out of any public repo**, it accumulates project- and user-specific notes). Entry format: `- [ ] YYYY-MM-DD | <skill-name or USER> | <observation> | <suggested change>`. Tick when processed.

## Channel 1 — Skill observations
Log when you notice (the signal list — check these, don't wait for them to hurt):
- **Non-compliance despite documentation**: a skill's rule existed, was loaded, and was still violated → the rule is unclear, buried, or fighting an instinct; rewrite it, don't just re-read it.
- **Dead weight**: a section never relevant across many sessions → candidate for deletion (lean skills work).
- **Just-in-case complexity**: machinery added speculatively that has never fired.
- **Repeated manual correction**: you or the user keep hand-fixing the same output class → missing rule.
- **Missing skill**: the same non-trivial pattern handled ad hoc ≥3 times → candidate NEW skill.

## Channel 2 — User-model observations (`USER` entries)
Log when interaction reveals something durable about how the user communicates or what they're aiming for:
- A correction that exposed a wrong reading of their intent (what did the phrasing actually mean?)
- Recurring vocabulary, shorthand, or framing worth learning ("handy" = staged + surfaced, not just documented)
- Goals that keep showing up beneath unrelated requests (recurring themes across sessions)
These graduate into persistent memory (`user`/`feedback` types) during the evolution pass — the log is the staging area, memory is the destination.

## Evolution pass (trigger: ≥5 unprocessed entries, or user asks)
1. Group entries by target skill / USER.
2. For each target, draft the minimal change: a rewritten rule, a deletion, a new memory entry, or (rarely) a new skill. Prefer 5-line fixes over rewrites; deletion is a first-class outcome.
3. **Present the batch to the user for approval before applying** — never autonomous (nobody benchmarks silent skill mutations; regressions hide).
4. Apply approved changes; tick entries; note the pass date at the top of the log.

## Pre-Flight Principle (applies always, not just in passes)
Before declaring any skill-guided task done: re-read that skill's rules and check the output against them explicitly. "The skill says X; did I do X?" Catches the compliance drift this whole loop exists to find.

## Rules
- Observations are one line. If it takes a paragraph, it's two observations or an essay — trim it.
- Don't log preferences the memory system already records; check first.
- The Delegation Playbook keeps its own ACE loop; delegation lessons go there, not here.
