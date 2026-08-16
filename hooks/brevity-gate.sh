#!/usr/bin/env bash
# brevity-gate.sh — Claude Code UserPromptSubmit hook: enforces TL;DR and scope
# discipline on short prompts, /wrap, and closure commands.
#
# Problem: the conductor rationalizes scope expansion on short commands.
# "/wrap" becomes a 500-word exploration of adjacent concerns. Behavioral
# conventions (a TL;DR-first-reports rule, a report-bracketing rule in the
# core file) are routinely violated when the model is mid-flow.
#
# Solution: inject a HARD scope+brevity constraint into context BEFORE the model
# generates its response. The constraint is proportional to prompt length: shorter
# prompts get stricter limits. /wrap and closure commands get the tightest.
#
# Trigger: UserPromptSubmit (fires on every user message)
# Fail-open: any error → exit 0 (no injection, no block)
# Kill switch: BREVITY_GATE_OFF=1
#
# Wired in ~/.claude/settings.json:
#   UserPromptSubmit → brevity-gate.sh

[ "${BREVITY_GATE_OFF:-0}" = "1" ] && exit 0

INPUT="$(cat 2>/dev/null)" || exit 0

python3 - "$INPUT" <<'PYEOF'
import sys, json, re

try:
    raw = sys.argv[1] if len(sys.argv) > 1 else ""
    data = json.loads(raw) if raw else {}
    prompt = (data.get("prompt") or "").strip()
    if not prompt:
        sys.exit(0)
except Exception:
    sys.exit(0)

words = len(prompt.split())
p = prompt.lower().strip()

# ── Closure commands: strictest constraint ──────────────────────────────
# /wrap, /compress, "done", "close it", "ship it", "that's it"
CLOSURE = re.compile(
    r"^/(wrap|compress|done)\b|"
    r"^(done|close it|ship it|that.s it|that.s all|we.re done|all good|"
    r"good to go|looks good|lgtm|ok$|okay$|cool$|thanks$|ty$|thx$)"
)

if CLOSURE.search(p):
    ctx = (
        "[BREVITY GATE — CLOSURE COMMAND] The user issued a short closure/approval "
        "command. Your response MUST obey ALL of these constraints:\n"
        "1. DO NOT expand scope. Do not say 'but also' or 'while we're at it' "
        "or 'one more thing.' The task is DONE unless the user reopens it.\n"
        "2. Open with **TL;DR:** (1-3 lines max: what was accomplished, status "
        "emoji). This is the ONLY mandatory content.\n"
        "3. Total response: under 100 words unless the user's command explicitly "
        "requests detail.\n"
        "4. End with the status line (🟢/🟡/🔴). Nothing after it.\n"
        "5. If /wrap triggers a multi-step procedure: execute it silently, "
        "then report with the same TL;DR constraint. Do not narrate each step.\n"
        "6. NO follow-up suggestions, no 'next time' advice, no 'you might "
        "also want to' addenda. The user will ask if they want more."
    )
    out = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": ctx,
        },
        "suppressOutput": True,
    }
    sys.stdout.write(json.dumps(out))
    sys.exit(0)

# ── Short prompts (≤10 words): tight constraint ────────────────────────
# These are quick instructions, not invitations for essays.
if words <= 10:
    ctx = (
        "[BREVITY GATE — SHORT PROMPT] The user's message is ≤10 words. "
        "Match response weight to input weight:\n"
        "- Open with **TL;DR:** if reporting results.\n"
        "- Total response: proportional to the ask. A 5-word instruction "
        "does not warrant a 200-word reply.\n"
        "- Do not expand scope beyond what was asked.\n"
        "- End with status line (🟢/🟡/🔴) if this completes a task.\n"
        "- No unsolicited follow-up suggestions."
    )
    out = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": ctx,
        },
        "suppressOutput": True,
    }
    sys.stdout.write(json.dumps(out))
    sys.exit(0)

# ── Medium prompts (11-20 words): lighter reminder ─────────────────────
if words <= 20:
    ctx = (
        "[BREVITY GATE — MEDIUM PROMPT] The user's message is brief (≤20 words). "
        "Keep response proportional. Open with **TL;DR:** on any report. "
        "Do not introduce tangential concerns or next-step suggestions "
        "unless the user asked for them."
    )
    out = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": ctx,
        },
        "suppressOutput": True,
    }
    sys.stdout.write(json.dumps(out))
    sys.exit(0)

# Prompts >20 words: no injection (normal session-router handles routing)
sys.exit(0)
PYEOF
