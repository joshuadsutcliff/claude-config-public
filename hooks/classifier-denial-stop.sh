#!/usr/bin/env bash
# classifier-denial-stop.sh — PostToolUse hook (matcher: Agent|Workflow).
# When an Agent/Workflow dispatch is denied by the auto-mode classifier,
# injects a hard stop directive preventing inline route-around.
#
# Purpose: Close the gap where the conductor treats a classifier denial as
# permission to execute inline. The conductor-inline-guard blocks the inline
# attempt mechanically; this hook makes the rule explicit in context so the
# model does not waste turns hitting the guard repeatedly.
#
# Kill switch: CLASSIFIER_DENIAL_STOP_OFF=1
# Fail-open: any parse error → exit 0

[ "${CLASSIFIER_DENIAL_STOP_OFF:-0}" = "1" ] && exit 0

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

python3 - "$input" <<'PYEOF'
import json, sys, re

try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)

# Only fire for the conductor (no agent_id)
agent_id = data.get("agent_id", "")
if agent_id:
    # This is a worker dispatching a sub-worker. Not our concern.
    sys.exit(0)

# Check if the tool result indicates a denial
tool_result = data.get("tool_result", "")
tool_error = data.get("tool_error", "")
exit_code = data.get("exit_code", 0)

# Combine all output for pattern matching
combined = ""
if isinstance(tool_result, str):
    combined += tool_result
if isinstance(tool_error, str):
    combined += " " + tool_error

# Also check if the result is structured
if isinstance(tool_result, dict):
    combined += " " + json.dumps(tool_result)

combined = combined.lower()

# Denial indicators from the auto-mode classifier
DENIAL_PATTERNS = [
    r"permission\s*(denied|rejected|refused)",
    r"not\s*allowed",
    r"blocked\s*by",
    r"auto.?mode.*denied",
    r"classifier.*denied",
    r"request\s*denied",
    r"cannot\s*proceed",
    r"action\s*not\s*permitted",
    r"policy\s*violation",
    r"safety\s*check\s*failed",
]

is_denial = False
for pattern in DENIAL_PATTERNS:
    if re.search(pattern, combined):
        is_denial = True
        break

# Also treat non-zero exit codes with empty/error results as potential denials
# But only if there's some denial-like language
if not is_denial and exit_code and exit_code != 0:
    # Non-zero exit alone is not enough (could be a legitimate error in the worker)
    # Only flag if the error text contains denial language
    pass

if not is_denial:
    sys.exit(0)

# ---- Inject stop directive ----
msg = (
    "[classifier-denial-stop] Your Agent dispatch was denied by the permission classifier. "
    "This is a STOP signal. Your options are:\n"
    "  1. Rewrite the brief to be more specific or less dangerous-looking.\n"
    "  2. Split the work into smaller, more clearly-scoped dispatches.\n"
    "  3. Report to the user that the classifier is blocking authorized work.\n\n"
    "You may NOT execute the denied work inline. The conductor-inline-guard "
    "will block you if you try. Attempting inline execution after a classifier "
    "denial is a standing-rule breach."
)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": msg,
    }
}))
PYEOF

exit 0
