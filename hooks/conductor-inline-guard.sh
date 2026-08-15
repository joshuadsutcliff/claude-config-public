#!/usr/bin/env bash
# conductor-inline-guard.sh — Claude Code PreToolUse hook (matcher: Bash|Write|Edit|NotebookEdit).
# HARD BLOCKER. The conductor NEVER writes files or runs commands.
# All execution delegates to workers. The conductor plans, briefs, reviews, judges.
#
# Worker detection strategy:
# A SessionStart hook (conductor-session-id.sh) records the conductor's session_id.
# This hook reads session_id from the PreToolUse input. If it matches the recorded
# conductor ID, this is the conductor — block. If it differs or no ID is recorded,
# this is a worker — allow (fail-open).
#
# This approach is reliable because workers always have a different session_id from
# the parent conductor session. No path-based heuristics needed.
#
# Override: CONDUCTOR_INLINE_OVERRIDE=1 (per-session env var, set manually by the user)
# Kill switch: CONDUCTOR_INLINE_GUARD_OFF=1

[ "${CONDUCTOR_INLINE_GUARD_OFF:-0}" = "1" ] && exit 0
[ "${CONDUCTOR_INLINE_OVERRIDE:-0}" = "1" ] && exit 0

# ═══════════════════════════════════════════════════════════════════════════════
# 2026-08-12: DISABLED. PreToolUse cannot distinguish conductor from worker
# (session_id and transcript_path are both inherited by workers). Every
# approach blocked workers too, deadlocking the entire session.
#
# Enforcement now handled by:
# - conductor-tripwire.sh (Stop hook, observational, detects inline execution)
# - efficient-conductor skill (behavioral: zero-write conductor rule)
# - The proportionality and delegation rules in CLAUDE.md convention 12
#
# This file is kept as the kill-switch mechanism (env vars above) and
# for potential future use if Claude Code adds a reliable conductor/worker
# discriminator to hook input.
# ═══════════════════════════════════════════════════════════════════════════════
exit 0

python3 - "$input" "$CONDUCTOR_ID_FILE" <<'PYEOF'
import json, sys, os

try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)

CONDUCTOR_ID_FILE = sys.argv[2]

# Read the recorded conductor session ID
try:
    with open(CONDUCTOR_ID_FILE) as f:
        conductor_id = f.read().strip()
except Exception:
    # Can't read the file — fail open
    sys.exit(0)

if not conductor_id:
    sys.exit(0)

# Get this call's session_id from the hook input
call_session_id = data.get("session_id", "")

# If the session_id matches the conductor's recorded ID, this is the conductor — BLOCK
# If it's different (worker) or empty (unknown context) — ALLOW
if call_session_id != conductor_id:
    sys.exit(0)

# This IS the conductor. Block the call.
tool_name = data.get("tool_name", "")
tool_input = data.get("tool_input", {}) if isinstance(data.get("tool_input"), dict) else {}

if tool_name == "Bash":
    command = tool_input.get("command", "")[:80]
    target_desc = f"Bash command: {command}"
elif tool_name in ("Write", "Edit", "NotebookEdit"):
    path = tool_input.get("file_path") or tool_input.get("path") or "(unknown)"
    target_desc = f"{tool_name} to: {path}"
else:
    sys.exit(0)

print(json.dumps({
    "decision": "block",
    "reason": (
        f"CONDUCTOR WRITE/EXECUTE BLOCKED. Attempted: {target_desc}\n\n"
        f"The conductor NEVER writes files or runs commands. This is absolute. "
        f"The conductor's tools are: Read, Search, List, Agent (spawn workers), "
        f"and verbal output to the user.\n\n"
        f"TO PROCEED: Spawn a worker with a brief describing what to write or run.\n"
        f"  - Opus (model: opus): for judgment-heavy writes (memories, playbook, "
        f"CLAUDE.md edits, knowledge entries, analysis docs)\n"
        f"  - Sonnet (model: sonnet): for session logs, file moves, git ops, code\n"
        f"  - Haiku (model: haiku): for mechanical reads, counts, classification\n\n"
        f"The judgment is deciding WHAT to write. The act of writing is execution. "
        f"Write the brief. Spawn the worker. Review the result."
    )
}))
PYEOF
