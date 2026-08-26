#!/usr/bin/env bash
# conductor-inline-guard.sh — Claude Code PreToolUse hook (matcher: Bash|Write|Edit|NotebookEdit).
# HARD BLOCKER. The conductor NEVER writes files or runs mutating commands.
# All execution delegates to workers. The conductor plans, briefs, reviews, judges.
#
# Discrimination: agent_id is present for subagents (workers) and absent for
# the conductor. Verified via diagnostic run across two sessions.
#
# Override: CONDUCTOR_INLINE_OVERRIDE=1 (per-session env var, set manually by the user)
# Kill switch: CONDUCTOR_INLINE_GUARD_OFF=1

[ "${CONDUCTOR_INLINE_GUARD_OFF:-0}" = "1" ] && exit 0
[ "${CONDUCTOR_INLINE_OVERRIDE:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.claude/state"
DIAG_LOG="${STATE_DIR}/conductor-guard-diagnostic.log"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

python3 - "$input" "$DIAG_LOG" <<'PYEOF'
import json, sys, time, os, re

try:
    data = json.loads(sys.argv[1])
except Exception:
    # Parse failure: fail open
    sys.exit(0)

log_file = sys.argv[2]

agent_id = data.get("agent_id", "")
agent_type = data.get("agent_type", "")
session_id = data.get("session_id", "")
tool_name = data.get("tool_name", "")
tool_input = data.get("tool_input", {}) if isinstance(data.get("tool_input"), dict) else {}

# ---- If agent_id is present, this is a worker: ALLOW ----
if agent_id:
    sys.exit(0)

# ---- This is the conductor. Check for read-only carve-outs. ----

if tool_name in ("Write", "Edit", "NotebookEdit"):
    # No carve-out for file writes. Block unconditionally.
    path = tool_input.get("file_path") or tool_input.get("path") or "(unknown)"
    target_desc = f"{tool_name} to: {path}"

elif tool_name == "Bash":
    command = (tool_input.get("command", "") or "").strip()
    if not command:
        sys.exit(0)

    # Read-only command whitelist. If the command starts with one of these
    # and contains no mutation operators, allow it.
    READ_ONLY_PREFIXES = [
        "cat ", "head ", "tail ", "wc ", "grep ", "egrep ", "fgrep ",
        "find ", "stat ", "file ", "echo ", "printf ", "which ", "type ",
        "date", "whoami", "hostname", "uname", "df ", "du ",
        "ls ", "ls\n", "pwd", "env", "printenv",
        "git status", "git log", "git diff", "git show",
        "git branch", "git remote", "git rev-parse", "git tag",
        "python3 -c \"import json", "python3 -c 'import json",
        "jq ", "sort ", "uniq ", "awk ", "cut ", "tr ",
        "test ", "[ ", "[[ ",
        "ssh ",  # ssh read commands handled below
        "curl -s", "curl --silent",  # GET-only curls
    ]

    # Mutation indicators that disqualify even whitelisted prefixes
    MUTATION_INDICATORS = re.compile(
        r'(>>?\s|[|]\s*(tee|dd|rm|mv|cp|chmod|chown|mkdir|install|git\s+(commit|push|checkout|reset|clean|branch\s+-[dD]))'
        r'|;\s*(rm|mv|cp|chmod|chown|mkdir|tee|dd|git\s+(commit|push))'
        r'|\bgit\s+(add|commit|push|checkout|reset|clean|branch\s+-[dD])\b'
        r'|\brm\b|\bmv\b|\bcp\b|\bmkdir\b|\bchmod\b|\bchown\b'
        r'|\bsed\s+-i\b|\binstall\b|\btee\b|\bdd\b'
        r'|\bdocker\s+(rm|rmi|stop|kill|exec|run|compose)'
        r'|\bsystemctl\s+(start|stop|restart|enable|disable)'
        r'|\blaunchctl\s+(load|unload|kickstart|kill)'
        r'|\bnohup\b|\b&\s*$'
        r'|\bsudo\b'
        r')',
        re.MULTILINE
    )

    # Check: does it start with a read-only prefix?
    is_read_prefix = False
    for prefix in READ_ONLY_PREFIXES:
        if command.startswith(prefix) or command.startswith(prefix.lstrip()):
            is_read_prefix = True
            break

    # Also allow: commands that are purely 'echo' (used for status pings)
    if command in ("echo pending", "echo done", "echo ok"):
        sys.exit(0)

    # Also allow: sleep (used for timing)
    if command.startswith("sleep "):
        sys.exit(0)

    # If it looks like a read and has no mutation indicators, allow it
    if is_read_prefix and not MUTATION_INDICATORS.search(command):
        sys.exit(0)

    # SSH: allow if the remote command is clearly read-only
    if command.startswith("ssh "):
        # Extract the remote command (everything after the last non-flag argument)
        # For safety, only allow if no mutation indicators in the whole thing
        if not MUTATION_INDICATORS.search(command):
            sys.exit(0)

    target_desc = f"Bash: {command[:120]}"

else:
    # Unknown tool matched somehow: fail open
    sys.exit(0)

# ---- BLOCK ----

# Log the block
ts = time.strftime("%Y-%m-%dT%H:%M:%S%z")
line = (
    f"{ts} | BLOCKED | caller=CONDUCTOR | session={session_id[:12]} | "
    f"tool={tool_name} | target={target_desc[:200]}\n"
)
try:
    with open(log_file, "a") as f:
        f.write(line)
except Exception:
    pass

# Emit block message on stderr and exit 2
msg = (
    f"CONDUCTOR EXECUTION BLOCKED. You attempted: {target_desc}\n\n"
    f"The conductor does not write files or run mutating commands. "
    f"This is enforced mechanically, not advisory.\n\n"
    f"If the auto-mode classifier denied your Agent dispatch:\n"
    f"  - STOP. Tell the user the classifier denied it and ask how to proceed.\n"
    f"  - Do NOT route around the denial by executing inline.\n\n"
    f"If you need this work done:\n"
    f"  - Rewrite the brief to be narrower or more specific.\n"
    f"  - Dispatch to a worker (sonnet for code/ops, haiku for reads/counts).\n"
    f"  - If delegation is structurally impossible, explain why to the user.\n\n"
    f"Override: the user can set CONDUCTOR_INLINE_OVERRIDE=1 for this session.\n"
)

sys.stderr.write(msg)
sys.exit(2)
PYEOF

exit 0
