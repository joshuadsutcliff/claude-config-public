#!/usr/bin/env bash
# session-timer.sh — Claude Code hook: session-length awareness nudge.
#
# Wired in ~/.claude/settings.json:
#   PostToolUse → session-timer.sh
#
# What it does: tracks session wall-clock elapsed time and injects an advisory
# nudge at 45 minutes and 90 minutes. At 90 minutes with 2+ worker failures,
# escalates to a degraded-session recommendation.
#
# NOT a block — purely informational injection. Fail-open: any error → exit 0.
#
# Env:
#   SESSION_TIMER_OFF=1    disable entirely (pass-through)

[ "${SESSION_TIMER_OFF:-}" = "1" ] && exit 0

# Session-scoped state keyed on the session_id every hook receives in its
# stdin JSON. CLAUDE_SESSION_ID is not exposed to hooks — a PID-based key
# gives a fresh PID per hook fire (orphaning one state file per fire), and a
# CWD-hash fallback shares ONE never-resetting state file across all
# sessions in a directory. The stdin payload's session_id is the supported,
# stable-per-session channel.
INPUT="$(cat)"
SID=$(printf '%s' "$INPUT" | python3 -c 'import sys, json
try:
    print(json.load(sys.stdin).get("session_id", ""))
except Exception:
    pass' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | cut -c1-64)
if [ -z "${SID:-}" ]; then
    # Degraded fallback: CWD hash — stable per-directory, shared across
    # sessions (nudges may not re-fire per session on this path).
    SID=$(printf '%s' "$PWD" | (md5sum 2>/dev/null || md5 2>/dev/null) | cut -c1-12)
fi
[ -z "${SID:-}" ] && SID="fallback"
STATE_DIR="/tmp/.claude-session-timer"
mkdir -p "$STATE_DIR" 2>/dev/null
# Hygiene: per-session keys accumulate — sweep state older than a day.
find "$STATE_DIR" -type f -mtime +1 -delete 2>/dev/null
STATE_FILE="$STATE_DIR/$SID"

# On first fire, record the start time.
if [ ! -f "$STATE_FILE" ]; then
    echo "$(date +%s) 0 0" > "$STATE_FILE"
    exit 0
fi

read -r START_TS NUDGE45 NUDGE90 < "$STATE_FILE" 2>/dev/null || exit 0
NOW=$(date +%s)
ELAPSED_MIN=$(( (NOW - START_TS) / 60 ))

# Count worker failures this session (from a session-scoped counter file).
FAILURE_COUNT=0
FAILURE_FILE="/tmp/.claude-worker-failures-$SID"
if [ -f "$FAILURE_FILE" ]; then
    FAILURE_COUNT=$(wc -l < "$FAILURE_FILE" | tr -d ' ')
fi

# 90-minute nudge (fires once; escalates if failures accumulated)
if [ "$ELAPSED_MIN" -ge 90 ] && [ "$NUDGE90" = "0" ]; then
    echo "$START_TS $NUDGE45 1" > "$STATE_FILE"
    if [ "$FAILURE_COUNT" -ge 2 ]; then
        python3 -c "
import json, sys
msg = (
    '[session-timer] DEGRADED SESSION: %s minutes elapsed with %s worker failures. '
    'This session is accumulating errors and cost. Recommend: report current state to the user, '
    'ask whether to /wrap and start fresh or continue. Long degraded sessions cost more '
    'per turn and produce lower-quality decisions.'
) % (sys.argv[1], sys.argv[2])
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': msg}}))" "$ELAPSED_MIN" "$FAILURE_COUNT"
    else
        python3 -c "
import json
msg = (
    '[session-timer] 90 minutes elapsed. This session is long. Consider: is the current '
    'task almost done? Would a /compact help? Should you report status and let the user decide '
    'whether to continue or /wrap? Long sessions degrade rule-compliance and raise per-turn cost.'
)
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': msg}}))"
    fi
    exit 0
fi

# 45-minute nudge (fires once)
if [ "$ELAPSED_MIN" -ge 45 ] && [ "$NUDGE45" = "0" ]; then
    echo "$START_TS 1 $NUDGE90" > "$STATE_FILE"
    python3 -c "
import json
msg = (
    '[session-timer] 45 minutes elapsed. Check: are you still on the original task? '
    'If scope has grown, report what you have and ask the user whether to continue or pivot.'
)
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': msg}}))"
    exit 0
fi

exit 0
