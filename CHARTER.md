# Charter — Enforced Runtime Integration Guide

> **Audience:** You are a frontier AI model (Claude, GPT, Gemini, or equivalent)
> assisting a user who wants to adopt this configuration into their own Claude
> Code setup. This document is your roadmap. Read it fully before making any
> changes to the user's existing config.

---

## What this config IS

A Claude Code configuration (`~/.claude/`) that turns agent-operation
conventions into **executable mechanical enforcement.** The distinguishing
property: rules are wired into shell-script hooks that `exit 2` (hard deny)
on violations — the model is physically blocked from the failure mode, not
merely asked to avoid it.

The system implements a **conductor/orchestra delegation model:**
- One expensive frontier model (the "conductor") sits in the main loop. It
  plans, judges, synthesizes, and reviews. It NEVER performs bounded execution.
- Cheaper worker models (Sonnet, Haiku, Opus) perform ALL token-heavy
  execution: research scans, code edits, test runs, log reduction.
- The enforcement layer (hooks) ensures this separation is mechanical, not
  voluntary. The conductor cannot accidentally or intentionally burn budget
  on worker-class tasks.

**Why it exists:** Written rules fail under task pressure. The model agrees
with every rule and then violates them when task-completion momentum builds.
This was proven empirically three times before the enforcement layer was
built. The hooks are scars from real incidents — each one maps to a specific,
documented failure that no amount of prompting could prevent.

---

## What this config is NOT

- Not a theme or UI customization
- Not a plugin pack (it's pure Claude Code config: hooks, agents, commands, skills)
- Not tied to a specific project or codebase (it's vault/workflow-agnostic)
- Not a replacement for the user's existing CLAUDE.md (it provides a template;
  the user's project-specific rules take precedence)
- Not opinionated about what the user works on — only about HOW the agent
  operates while doing it

---

## Prerequisites

Before integration:
1. **Claude Code CLI** installed and working (`claude --version`)
2. **An Obsidian vault** (or any working directory) where Claude Code runs
3. **`~/.claude/` directory exists** with at least a `settings.json`
4. The user understands they are adopting an enforcement-first philosophy:
   the hooks WILL block certain model behaviors mechanically. This is the
   point, not a side effect.

---

## Integration plan (follow in order)

### Phase 1 — Assessment (read-only, no changes)

Before touching anything, assess the user's existing setup:

```bash
# What exists already?
ls ~/.claude/
ls ~/.claude/hooks/ 2>/dev/null
ls ~/.claude/agents/ 2>/dev/null
ls ~/.claude/skills/ 2>/dev/null
ls ~/.claude/commands/ 2>/dev/null
cat ~/.claude/settings.json
```

**Document what you find.** The integration must MERGE, not overwrite.
Specifically:
- Existing hooks in `settings.json` → keep them; ADD the new hooks alongside
- Existing agents → keep them; ADD the new agents if no name collision
- Existing skills → keep them; ADD the new skills
- Existing commands → keep them; ADD only commands the user wants
- Existing `settings.json` model/effort/permissions → NEVER overwrite without
  explicit user consent

### Phase 2 — Core enforcement (the minimum viable adoption)

These three items are the foundation. Everything else is optional.

**Step 1: Install `usage-guard.sh`**

Copy `hooks/usage-guard.sh` to `~/.claude/hooks/`.

Wire it into `settings.json`:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent|Workflow",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/usage-guard.sh block"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/usage-guard.sh refresh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/usage-guard.sh inform"
          }
        ]
      }
    ]
  }
}
```

**What it does:** Denies any subagent spawn that would inherit the conductor
model. Hard-blocks all spawns at ≥90% usage. Warns at ≥70%. Requires
`ccusage` (install: `npx -y ccusage@20`; version-pinned to prevent breaking
schema changes from silently disabling the guard).

**Verify:** `bash -n ~/.claude/hooks/usage-guard.sh` exits 0.

**Step 2: Install `session-router.sh`**

Copy `hooks/session-router.sh` to `~/.claude/hooks/`.

Add to the `UserPromptSubmit` array in `settings.json`:
```json
{
  "type": "command",
  "command": "bash ~/.claude/hooks/session-router.sh"
}
```

**What it does:** Classifies every prompt LIGHT/MEDIUM/HEAVY and injects a
routing policy. HEAVY tasks get a binding plan-then-stop gate (the model MUST
show its plan and wait for user approval before executing).

**Step 3: Install worker agents**

Copy `agents/*.md` to `~/.claude/agents/`. These define the named worker
roles the conductor delegates to:
- `researcher.md` — read-only evidence gathering (model: sonnet, effort: low)
- `code-generator.md` — bounded code edits (model: sonnet)
- `tester.md` — test execution + log reduction (model: haiku)
- `code-reviewer.md` — reviews completed work against its plan (model: sonnet)

**Verify:** Start a new Claude Code session. Ask it to do something that
requires research ("scan the project for unused imports"). It should delegate
to the researcher agent, not do it inline.

### Phase 3 — Behavioral layer (recommended but optional)

**Step 4: Install `efficient-fable` skill**

Copy `skills/efficient-fable/` to `~/.claude/skills/efficient-fable/`.

This is the conductor's operating manual — it defines:
- The delegation pattern (when to delegate vs. keep inline)
- The mechanical/reasoning routing test (Haiku vs. Sonnet vs. Opus)
- Worker handoff packet requirements (falsifiability contract)
- Conductor field rules (parallel ceiling, two-strike rule, stuck rule, etc.)

It's marked ALWAYS-ON in its description — it fires every session.

**Step 5: Install remaining skills (optional, pick what fits)**

Each skill is independent. Install only the ones relevant to the user's work:
- `consequence-simulation` — premortem + 2nd-order effects before irreversible actions
- `detached-judgment` — counter sycophancy and anchoring
- `grill-me` — interrogate underspecified requirements before planning
- `model-council` — convene non-Claude models as independent reviewers
- `nod-protocol` — "Negate Own Default" — stress-test a fast conclusion
- `parallel-lens-synthesis` — multi-lens analysis for high-stakes decisions
- `pressure-test` — adversarial critique across fixed lenses
- `skill-evolution` — the self-improvement loop (logs friction, batches fixes)
- `stay-within-limits` — usage-cap discipline for long-running work
- `quick-recap` — the 🟢/🟡/🔴 status-line convention

**Step 6: Install session-lifecycle commands (optional)**

Commands in `commands/` implement the session bracket pattern:
- `/resume` — orient at session start
- `/wrap` — unified session close (preserve → compress → sync)
- `/compress` — save session log
- `/preserve` — route a durable decision to long-term memory

These are Obsidian-vault-aware. If the user doesn't use Obsidian, adapt the
file paths or skip them.

### Phase 4 — Supplementary enforcement (for heavy users)

**Step 7: Install supplementary hooks**

These are additional hooks beyond the core two, for users who want full
coverage:
- `session-timer.sh` — nudges at 45/90 minutes of session runtime
- `conductor-tripwire.sh` — flags execution-shaped conductor output at
  session end (the observability layer). **NOTE: this hook is currently
  STAGED in the repo, not wired. Review its header comments before wiring
  it into settings.json — it requires a conformance review pass before
  going live. Install it as a file but do NOT wire it until the user has
  validated its behavior in their environment.**
- `hook-health-check.sh` — verifies all hooks are callable at session start
- `post-compact.sh` — re-grounds the model after auto-compaction

Each needs wiring into `settings.json` at its appropriate event hook
(PostToolUse, Stop, SessionStart). See `_index.md` for hooks that are
already indexed; `session-timer.sh` and `conductor-tripwire.sh` are
supplementary and documented in their own file headers.

---

## Customization points (what the user SHOULD change)

| Component | What to customize | Why |
|---|---|---|
| `session-router.sh` HEAVY keywords | Add domain-specific keywords that signal complex work in the user's field | The default keywords are infrastructure/coding-focused |
| `session-router.sh` credential patterns | Add the user's specific service names, host IPs, domain names | The defaults are generic |
| `usage-guard.sh` COST_LIMIT | Calibrate against the user's actual usage cap | Default is $250; your cap may differ |
| Worker agent `effort:` pins | Adjust if the user's tasks need more/less worker reasoning | Defaults are `low` for mechanical workers |
| Commands file paths | Adapt vault paths if not using Obsidian, or using a different folder structure | Commands assume an Obsidian vault layout |
| Skill descriptions | Tune trigger conditions to match the user's actual work patterns | Skills auto-fire on description match |

---

## What NEVER to change

- **Hook fail-open behavior** — hooks must exit 0 on any error. A broken
  hook that blocks prompts will brick the user's Claude Code session.
- **The model-floor enforcement (Policy 1)** — workers must always specify
  an explicit model. Removing this undoes the entire economic model.
- **The ≥90% hard-block** — this is the budget's last line of defense.
  Lowering it risks cap exhaustion with no recovery.
- **`settings.json` model/effort** — never change the user's default model
  or effort level without explicit consent. These are personal preferences
  that the config must respect.

---

## Validation checklist (run after integration)

```bash
# All hooks parse cleanly
for hook in ~/.claude/hooks/*.sh; do
    bash -n "$hook" && echo "OK: $hook" || echo "FAIL: $hook"
done

# settings.json is valid JSON
python3 -c "import json; json.load(open('$HOME/.claude/settings.json'))"

# Usage guard responds
bash ~/.claude/hooks/usage-guard.sh pct

# Session router classifies a test prompt
printf '{"prompt":"refactor the entire authentication module"}' | \
    bash ~/.claude/hooks/session-router.sh

# Agents exist and are readable
ls ~/.claude/agents/*.md
```

If all pass, start a new Claude Code session. The hooks activate on session
start (settings.json is read once at launch).

---

## Architectural principles (for the integrating model to internalize)

1. **Mechanical over behavioral.** If a rule can be a hook, make it a hook.
   Written rules fail under task pressure; hooks don't.

2. **Fail-open always.** A broken hook must never block the user. Silent
   degradation is better than a bricked session.

3. **The conductor's scarcity is the constraint.** The frontier model's
   weekly cap is the binding resource. Everything is designed to minimize
   conductor token burn while maximizing judgment quality.

4. **Trust is not a control.** "The model will follow this rule" is not a
   safety mechanism. "The hook denies the action before it starts" is.

5. **Every hook is a scar.** Each one maps to a real incident. Don't remove
   a hook because it seems excessive — it exists because the model proved
   the failure mode is real.

6. **Host project rules win.** This config provides operating discipline.
   The user's project-specific rules (coding standards, deployment gates,
   domain knowledge) always take precedence on conflict.

---

## Quick-start (for users who just want the essentials)

```bash
# Clone the repo
git clone https://github.com/joshuadsutcliff/claude-config-public.git /tmp/enforced-runtime

# Copy the core enforcement
mkdir -p ~/.claude/hooks ~/.claude/agents
cp /tmp/enforced-runtime/hooks/usage-guard.sh ~/.claude/hooks/
cp /tmp/enforced-runtime/hooks/session-router.sh ~/.claude/hooks/
cp /tmp/enforced-runtime/agents/*.md ~/.claude/agents/
chmod +x ~/.claude/hooks/*.sh

# Merge hook wiring into your settings.json (DON'T overwrite — merge)
# See Phase 2 above for the exact JSON to add

# Verify
bash -n ~/.claude/hooks/usage-guard.sh
bash -n ~/.claude/hooks/session-router.sh
echo "Ready. Start a new claude session."
```

---

## Support and evolution

This config is maintained by one person. It evolves from real usage — every
hook, rule, and skill was born from an incident, tested against real sessions,
and measured with before/after telemetry. It's not theoretical.

The canonical source is this repository. The architecture docs
(`docs/ARCHITECTURE.md`) explain the design; `AGENT.md` is the operating
contract; `_index.md` is the asset registry. Start with `AGENT.md`.

MIT licensed. Take what's useful; adapt what doesn't fit; ignore what doesn't
apply to your workflow.
