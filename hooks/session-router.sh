#!/usr/bin/env bash
# session-router.sh — Claude Code hook: automatic session-tier classifier.
#
# Wired in ~/.claude/settings.json:
#   UserPromptSubmit → session-router.sh   (runs alongside usage-guard.sh inform)
#
# What it does: reads the submitted prompt, classifies it LIGHT / MEDIUM / HEAVY
# with cheap regex heuristics, and injects a routing directive into the conductor's
# context for that turn (hookSpecificOutput.additionalContext).
#
# HARD LIMIT (verified against Claude Code v2.1.179 docs): a hook CANNOT change the
# main-loop model or effort level — those are read-once at session start and only the
# interactive /model and /fast commands change them. So this router is BEHAVIORAL: it
# tells the conductor *when to delegate down* to sonnet/haiku workers and *when to stay
# terse*. The real model-tier savings come from delegation (MEDIUM/HEAVY), which the
# usage-guard hook already enforces. For LIGHT turns the lever is brevity + no fan-out.
#
# Fail-open: any parse error or missing python3 → exit 0 with no injection. A broken
# router must never block a prompt.
#
# Env:
#   SESSION_ROUTER_SHOW=1   also surface a one-line "session-router: TIER" systemMessage
#   SESSION_ROUTER_OFF=1    disable classification entirely (pass-through)

[ "${SESSION_ROUTER_OFF:-}" = "1" ] && exit 0

INPUT="$(cat)"

python3 - "$INPUT" <<'PYEOF'
import sys, json, re, os

try:
    raw = sys.argv[1] if len(sys.argv) > 1 else ""
    data = json.loads(raw) if raw else {}
    prompt = data.get("prompt") or ""
    if not prompt.strip():
        sys.exit(0)

    # Background task-notifications are system events, not user prompts — classifying
    # them fired the HEAVY gate on every worker-completion turn (added 2026-07-26,
    # observed 6x in one session). Skip classification entirely for these turns.
    head = prompt.lstrip()[:200]
    if head.startswith("[SYSTEM NOTIFICATION") or "<task-notification>" in head:
        sys.exit(0)

    p = prompt.lower()
    words = len(prompt.split())

    # Codebase-spanning / multi-step / build-from-scratch work → full conductor design.
    HEAVY = [
        r"\brefactor", r"\bmigrat", r"\baudit", r"\bimplement", r"\brewrite",
        r"\boverhaul", r"\bscaffold", r"\barchitect", r"\bredesign", r"\bport\b",
        r"across the (codebase|repo|repository|project|files)",
        r"\ball (the )?(files|modules|tests|components|callers)",
        r"every (file|module|test|component|caller)",
        r"whole (codebase|repo|repository|project)",
        r"end[- ]to[- ]end", r"\btest suite\b", r"\bbenchmark", r"\bdeep research\b",
        r"phased[- ]review", r"\bbuild (a|an|the|out|me) ", r"\bset up (a|an|the) ",
        # Windows/AD infra work is conductor-grade even when tersely phrased
        # (added 2026-07-16 — router under-called GPO/DC marathons as LIGHT/MEDIUM):
        r"\bgpo\b", r"\bfsmo\b", r"\bsysvol\b", r"\bgpmc\b", r"\bauditpol\b",
        r"\bwef\b", r"\bdomain controller", r"\bdcpromo\b", r"\bdemote\b",
        r"\bgroup policy\b", r"\bactive directory\b", r"\bwsus\b",
    ]
    # Bounded execution work → delegate the heavy lifting to a sonnet/haiku worker.
    MEDIUM = [
        r"\bfix\b", r"\bbug\b", r"\badd\b", r"\bupdate\b", r"\bcreate\b",
        r"\bwrite (a|an|the|me|some)\b", r"\bedit\b", r"\bchange\b", r"\bmodify\b",
        r"\binstall\b", r"\bconfigure\b", r"\bdebug\b", r"\bremove\b", r"\brename\b",
        r"\bgenerate\b", r"\bscript\b", r"\bdiagnose\b", r"\binvestigate\b",
    ]
    # Quick / conversational / factual → answer directly, no fan-out.
    LIGHT = [
        r"^\s*(what|where|when|who|which|why|how|is|are|can|could|does|do|should|will)\b",
        r"\bexplain\b", r"\bwhat is\b", r"\bconfirm\b", r"\bquick question\b",
        r"\btypo\b", r"\bremind me\b", r"\bdoes .* support\b", r"\bcan you tell me\b",
    ]

    # Opinion/advisory-shaped prompts down-weight to LIGHT even when entity-dense,
    # unless they also contain an explicit action verb (added 2026-07-25 — recurring
    # over-classification of "what do you think / thoughts on / should I A or B" turns).
    ADVISORY = [
        r"what do you think", r"your thoughts", r"thoughts on",
        r"should i .* or ", r"sound good", r"is .* a good idea",
        r"would you recommend", r"\ba or b\b",
    ]
    ACTION_VERBS = [
        r"\bfix\b", r"\binstall\b", r"\bbuild\b", r"\bdeploy\b",
        r"\brefactor\b", r"\brun\b", r"\bcreate\b", r"\bmigrat",
    ]

    def hits(pats):
        return sum(1 for pat in pats if re.search(pat, p))

    is_advisory = hits(ADVISORY) > 0
    has_action_verb = hits(ACTION_VERBS) > 0

    if is_advisory and not has_action_verb:
        sys.exit(0)

    sh, sm, sl = hits(HEAVY), hits(MEDIUM), hits(LIGHT)

    if (sh > 0 and words > 40) or words > 180:
        tier = "HEAVY"
    elif sh > 0 and words <= 40:
        tier = "MEDIUM"  # short prompts with heavy keywords → MEDIUM, not HEAVY
    elif sl > 0 and sm == 0 and words <= 40:
        tier = "LIGHT"
    elif sm > 0 or words > 70:
        tier = "MEDIUM"
    elif words <= 20:
        tier = "LIGHT"
    else:
        tier = "MEDIUM"

    # LIGHT injects nothing — brevity lives in standing rules (Kiro adjudication 2026-07-21)
    if tier == "LIGHT":
        sys.exit(0)

    POLICY = {
        "LIGHT": (
            "Quick/conversational turn. Answer directly and concisely; do NOT spawn "
            "subagents or parallel tool calls; keep tool use to the minimum needed. "
            "The hook cannot lower the main-loop model/effort, so brevity is the lever "
            "— don't pad. If many light turns run back-to-back while effort is pinned "
            "high, you may once suggest the user run /fast."
        ),
        "MEDIUM": (
            "Bounded execution work. Delegate the token-heavy lifting (repo/doc scans, "
            "candidate edits, repetitive changes, test/log runs) to a sonnet/haiku worker "
            "(researcher / code-generator / tester) and keep the main loop to framing, "
            "judging, and relaying. Don't do the heavy lifting yourself."
        ),
        "HEAVY": (
            "HEAVY task detected. You MUST plan before executing. In this turn:\n"
            "1. State the full scope (all files/systems that will be touched, all workers needed).\n"
            "2. Break the work into numbered atomic steps — each step ≤1 worker spawn and ≤3 files.\n"
            "3. State which step you will do FIRST.\n"
            "4. STOP. Do not begin execution. Wait for the user's explicit go.\n"
            "5. Estimate: ~N workers, ~M minutes, approximate cost if you can infer from similar recent tasks.\n\n"
            "Do NOT begin execution in this response. Planning output only. "
            "If the task is genuinely a single atomic action (one file, one command), "
            "say so and execute it — this gate is for multi-step work, not one-liners. "
            "The session-router hook injected this constraint mechanically; it is not optional."
        ),
    }

    if tier == "HEAVY":
        msg = ("[session-router] Tier: HEAVY (mechanical plan-then-stop gate — "
               "binding; the only escape hatch is the single-atomic-action clause "
               "in the policy itself). Policy: %s" % POLICY[tier])
    else:
        msg = ("[session-router] Tier: %s (heuristic prior — override with your own "
               "judgment if the task is actually lighter/heavier). Policy: %s"
               % (tier, POLICY[tier]))

    out = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": msg,
        },
        "suppressOutput": True,
    }
    if os.environ.get("SESSION_ROUTER_SHOW") == "1":
        out["systemMessage"] = "session-router: %s" % tier

    sys.stdout.write(json.dumps(out))
except Exception:
    sys.exit(0)
PYEOF

exit 0
