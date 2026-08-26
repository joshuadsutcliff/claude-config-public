#!/usr/bin/env bash
# reconcile-nudge.sh — PostToolUse hook (matcher: Agent|Workflow|TaskOutput).
# Counts completed task-notifications per session. When >=8 completions have
# occurred without a task-tracking-file update, injects an advisory reminder
# to reconcile.
#
# Purpose: Prevent a running task-tracking file from drifting during long
# sessions where many items close without being marked. A prior long session
# had 17 closures with no reconcile until the user explicitly asked.
#
# Non-blocking (exit 0 with additionalContext). Rate-limited: one nudge per
# 30 minutes per session.
#
# Kill switch: RECONCILE_NUDGE_OFF=1

[ "${RECONCILE_NUDGE_OFF:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.claude/state"
STATE_FILE="${STATE_DIR}/reconcile-nudge.json"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

python3 - "$input" "$STATE_FILE" <<'PYEOF'
import json, sys, os, time

try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)

state_file = sys.argv[2]

# Only fire for the conductor (no agent_id) receiving a task completion
agent_id = data.get("agent_id", "")
if agent_id:
    sys.exit(0)

# Check if this is a task completion notification
tool_result = data.get("tool_result", "")
if isinstance(tool_result, dict):
    tool_result = json.dumps(tool_result)
if not isinstance(tool_result, str):
    tool_result = str(tool_result)

# Look for completion indicators
is_completion = any(x in tool_result.lower() for x in [
    "completed", "finished", "done", "success",
    "status\": \"completed", "status>completed"
])

if not is_completion:
    sys.exit(0)

# Load state
session_id = data.get("session_id", "unknown")
try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    state = {}

sess = state.get(session_id, {}) if isinstance(state.get(session_id), dict) else {}
completions = int(sess.get("completions", 0)) + 1
last_nudge = float(sess.get("last_nudge_ts", 0))
last_reconcile = float(sess.get("last_reconcile_ts", 0))

sess["completions"] = completions

# Reset counter if a task-tracking-file update happened (detected by tool_result
# mentioning the tracked filename — adapt TRACK_FILE to your own convention)
TRACK_FILE = "NOW.md"
if TRACK_FILE in tool_result or TRACK_FILE.lower() in tool_result.lower():
    sess["completions"] = 0
    sess["last_reconcile_ts"] = time.time()
    state[session_id] = sess
    try:
        tmp = state_file + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f)
        os.replace(tmp, state_file)
    except Exception:
        pass
    sys.exit(0)

now = time.time()
should_nudge = completions >= 8 and (now - last_nudge) >= 1800  # 30 min cooldown

if should_nudge:
    sess["last_nudge_ts"] = now

state[session_id] = sess

# Persist
try:
    tmp = state_file + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, state_file)
except Exception:
    pass

if should_nudge:
    msg = (
        f"[reconcile-nudge] {completions} task completions this session without a "
        f"task-tracking-file update. Consider running a mid-session reconcile to "
        f"keep the tracking surface truthful. Stale items mislead future orientation."
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": msg,
        }
    }))

PYEOF

exit 0
