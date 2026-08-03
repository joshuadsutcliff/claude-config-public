#!/usr/bin/env bash
# hook-health-check.sh — SessionStart hook: verify all hooks are callable.
#
# Runs once at session start. Checks syntax (bash -n) on every .sh hook,
# confirms python3 is available, and confirms state directories exist.
# If anything fails, injects a warning into context. Fail-open: a broken
# health-check must not block session start.
#
# Env:
#   HOOK_HEALTH_OFF=1    disable entirely

[ "${HOOK_HEALTH_OFF:-}" = "1" ] && exit 0

HOOKS_DIR="${HOME}/.claude/hooks"
FAILURES=""

# Check each hook script for syntax
for hook in "$HOOKS_DIR"/*.sh; do
    [ -f "$hook" ] || continue
    [ "$(basename "$hook")" = "hook-health-check.sh" ] && continue
    if ! bash -n "$hook" 2>/dev/null; then
        FAILURES="${FAILURES}$(basename "$hook") FAILED bash -n; "
    fi
done

# Check python3 availability (required by session-router, usage-guard,
# session-timer, post-compact, conductor-tripwire)
if ! command -v python3 >/dev/null 2>&1; then
    FAILURES="${FAILURES}python3 NOT FOUND (multiple hooks depend on it); "
fi

# Check state directories exist or are creatable
for dir in "${TMPDIR:-/tmp}/.claude-session-timer" "${HOME}/.cache"; do
    if ! mkdir -p "$dir" 2>/dev/null; then
        FAILURES="${FAILURES}cannot create $dir; "
    fi
done

# Check spawn-rate log is writable
SR_LOG="${HOME}/.cache/claude-spawn-rate.log"
if ! touch "$SR_LOG" 2>/dev/null; then
    FAILURES="${FAILURES}spawn-rate log $SR_LOG not writable; "
fi

if [ -n "$FAILURES" ]; then
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json, sys
msg = '[hook-health] WARNING — some hooks are INOPERATIVE this session: ' + sys.argv[1] + 'The mechanical enforcement layer may be degraded. Report this to the user.'
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': msg}}))" "$FAILURES" 2>/dev/null
    else
        # python3 itself is the failure — plain stdout still reaches context
        # from a SessionStart hook, so the warning is not lost.
        echo "[hook-health] WARNING — some hooks are INOPERATIVE this session: ${FAILURES}The mechanical enforcement layer may be degraded. Report this to the user."
    fi
fi

exit 0
