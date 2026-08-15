#!/usr/bin/env bash
# model-swap-detector.sh — PostToolUse hook: detect mid-session model switches.
#
# Reads the session transcript JSONL and checks whether the model field
# on assistant turns has changed from the session's first model. If a
# swap is detected, injects a hard warning into context.
#
# Fires every CHECK_INTERVAL tool calls (default: 5). Once a swap is
# detected and warned, it doesn't re-warn (one-shot per swap event).
#
# Fail-open: any error → exit 0.
#
# Env:
#   MODEL_SWAP_DETECTOR_OFF=1    disable entirely
#   MODEL_SWAP_CHECK_INTERVAL=5  check every N tool calls (default 5)

[ "${MODEL_SWAP_DETECTOR_OFF:-}" = "1" ] && exit 0

CHECK_INTERVAL="${MODEL_SWAP_CHECK_INTERVAL:-5}"
STATE_DIR="${TMPDIR:-/tmp}/.claude-model-swap"
mkdir -p "$STATE_DIR" 2>/dev/null

INPUT="$(cat)"

# Extract session_id and transcript_path from stdin
SESSION_ID=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    print(d.get('session_id', ''))
except: pass
" "$INPUT" 2>/dev/null)

TRANSCRIPT_PATH=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    print(d.get('transcript_path', ''))
except: pass
" "$INPUT" 2>/dev/null)

[ -z "$SESSION_ID" ] && exit 0

STATE_FILE="$STATE_DIR/$SESSION_ID"

# Increment counter, check if we should inspect this call
COUNT=0
WARNED=0
if [ -f "$STATE_FILE" ]; then
    read -r COUNT WARNED < "$STATE_FILE" 2>/dev/null || { COUNT=0; WARNED=0; }
fi
COUNT=$((COUNT + 1))
echo "$COUNT $WARNED" > "$STATE_FILE" 2>/dev/null

# Only check every CHECK_INTERVAL calls (and only if not already warned)
[ "$WARNED" = "1" ] && exit 0
[ $((COUNT % CHECK_INTERVAL)) -ne 0 ] && exit 0

# If transcript_path isn't in the payload, try to find it
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    # Fallback: find the session JSONL by session_id
    PROJECTS_DIR="${HOME}/.claude/projects"
    if [ -d "$PROJECTS_DIR" ]; then
        TRANSCRIPT_PATH=$(find "$PROJECTS_DIR" -name "${SESSION_ID}.jsonl" -type f 2>/dev/null | head -1)
    fi
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Check for model transitions in the transcript
SWAP_INFO=$(python3 -c "
import json, sys

transcript = sys.argv[1]
models = []
try:
    with open(transcript) as f:
        for line in f:
            try:
                d = json.loads(line)
            except:
                continue
            if d.get('type') != 'assistant' or d.get('isSidechain'):
                continue
            m = d.get('message', {}).get('model', '') or ''
            if not m.startswith('claude-'):
                continue
            if not models or models[-1] != m:
                models.append(m)
except:
    sys.exit(0)

if len(models) > 1:
    print(f'SWAP:{models[0]}:{models[-1]}:{len(models) - 1}')
else:
    print('OK')
" "$TRANSCRIPT_PATH" 2>/dev/null)

if echo "$SWAP_INFO" | grep -q "^SWAP:"; then
    ORIGINAL=$(echo "$SWAP_INFO" | cut -d: -f2)
    CURRENT=$(echo "$SWAP_INFO" | cut -d: -f3)
    TRANSITIONS=$(echo "$SWAP_INFO" | cut -d: -f4)

    # Mark as warned (one-shot)
    echo "$COUNT 1" > "$STATE_FILE" 2>/dev/null

    python3 -c "
import json, sys
original = sys.argv[1]
current = sys.argv[2]
transitions = sys.argv[3]
q = chr(34)
msg = (
    '[MODEL SWAP DETECTED — CONDUCTOR BATON HANDOFF] This session started '
    'on %s but is now running as %s (%s model transition(s) in the '
    'transcript). The cause is not knowable from inside the session: it '
    'may be a safeguard auto-switch, a manual /model change by the user, or '
    'a cap-exhaustion fallback. Do NOT assert a cause; ask the user if it '
    'matters. '
    'YOUR STATUS: You (%s) are now the TEMPORARY CONDUCTOR for the '
    'remainder of this session. The full conductor/orchestra delegation '
    'contract (efficient-conductor skill, CLAUDE.md rules 12-17, all hooks '
    'and enforcement) applies to you IDENTICALLY as it would to the primary '
    'frontier-model advisor. You are not a worker — you hold the baton. Delegate to '
    'workers (Sonnet/Haiku) the same way the frontier-model advisor would. The HEAVY gate, '
    'spawn-rate limiter, predictive injections, and all behavioral rules '
    'are YOURS to follow now. '
    'IDENTITY: Your system prompt still says %s — it is STALE. You are '
    '%s. Do NOT assert you are %s. If the user asks what model you are, say: '
    + q + 'A mid-session model swap occurred. I am %s, holding the '
    'conductor baton temporarily for this session.' + q + ' '
    'CONTINUITY: Pick up exactly where the session left off. Read the '
    'last user message and continue the work. Do not re-orient, do not '
    '/resume, do not start fresh — you inherited a live session.'
) % (original, current, transitions, current, original, current, original, current)
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'additionalContext': msg
    }
}))" "$ORIGINAL" "$CURRENT" "$TRANSITIONS"
    exit 0
fi

exit 0
