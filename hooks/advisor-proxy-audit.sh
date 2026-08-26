#!/usr/bin/env bash
# advisor-proxy-audit.sh -- Stop hook: post-hoc audit for conductor-direct advisor calls.
#
# The advisor is a server tool. No PreToolUse hook can intercept it because the
# call never enters the local hook pipeline. This Stop hook scans the session
# transcript after the fact and flags any conductor-originated advisor calls.
#
# Architecture: detect, not prevent. The proxy convention exists for transcript
# hygiene (the advisor model refuses permanently if the transcript contains
# secrets). This hook reports violations so they're visible, not silently
# swallowed.
#
# What it looks for: tool_use blocks with name containing "advisor" that appear
# in assistant messages WITHOUT an agent_id (i.e., conductor turns).
# Worker-originated calls are expected and not flagged.
#
# Response: if violations found, injects a reminder via stdout. Non-blocking.
# Logs all findings to ~/.claude/state/advisor-proxy-audit.log.
#
# Kill switch: ADVISOR_PROXY_AUDIT_OFF=1
# Fail-open: any error -> exit 0
#
# Replaces the dead PreToolUse advisor-proxy-guard.sh.

[ "${ADVISOR_PROXY_AUDIT_OFF:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.claude/state"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

{
    PY_SCRIPT="${STATE_DIR}/.advisor-proxy-audit.py.$$"
    cat > "$PY_SCRIPT" <<'PYEOF'
import json, sys, os, time

try:
    payload = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)

if not isinstance(payload, dict):
    sys.exit(0)

state_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.claude/state")

transcript_path = payload.get("transcript_path", "")
session_id = payload.get("session_id", "") or "unknown"

if not transcript_path or not os.path.isfile(transcript_path):
    sys.exit(0)

# Scan the transcript for advisor tool_use blocks from the conductor
violations = []
try:
    with open(transcript_path, "r", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except Exception:
                continue

            # Only assistant messages
            if msg.get("type") != "assistant":
                continue

            # If there's an agent_id anywhere in the message envelope, it's a worker
            if msg.get("agent_id"):
                continue

            # Check content for advisor tool_use
            message = msg.get("message", {})
            content = message.get("content", [])
            if not isinstance(content, list):
                continue

            for block in content:
                if block.get("type") != "tool_use":
                    continue
                tool_name = block.get("name", "").lower()
                if "advisor" in tool_name:
                    violations.append({
                        "tool_name": block.get("name", ""),
                        "tool_use_id": block.get("id", "")[:16],
                    })
except Exception:
    sys.exit(0)

# Log results
log_file = os.path.join(state_dir, "advisor-proxy-audit.log")
ts = time.strftime("%Y-%m-%dT%H:%M:%S%z")

if violations:
    try:
        with open(log_file, "a") as f:
            for v in violations:
                f.write(f"{ts} | VIOLATION | conductor called advisor directly | "
                        f"session={session_id[:12]} | tool_use_id={v['tool_use_id']}\n")
    except Exception:
        pass

    # Inject a reminder (non-blocking, advisory only)
    reminder = {
        "hookSpecificOutput": {
            "additionalContext": (
                f"[advisor-proxy-audit] This session had {len(violations)} direct "
                f"conductor-to-advisor call(s). The proxy convention exists to keep "
                f"the advisor's transcript clean of secrets and credential content. "
                f"Use the advisor-proxy command for future consults."
            )
        }
    }
    print(json.dumps(reminder))
else:
    # Clean session, log one line
    try:
        with open(log_file, "a") as f:
            f.write(f"{ts} | CLEAN | session={session_id[:12]}\n")
    except Exception:
        pass

sys.exit(0)
PYEOF

    out=$(printf '%s' "$input" | python3 "$PY_SCRIPT" "$STATE_DIR" 2>/dev/null)
    rc=$?
    rm -f "$PY_SCRIPT" 2>/dev/null
    [ -n "$out" ] && printf '%s' "$out"
    exit $rc
} || exit 0
