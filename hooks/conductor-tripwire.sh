#!/usr/bin/env bash
# conductor-tripwire.sh — Claude Code Stop hook: mid-session execution-shape tripwire.
#
# Purpose: catch rationalized inline execution by the conductor ("managing AND
# playing") that the bait battery structurally cannot — a brief-then-judge turn
# has ~0-1 main-loop mutations; an execution turn has many. Deviates from a
# PostToolUse/token-count design (Kiro's original proposal) because tool-call
# shape is deterministic where token volume requires fuzzy classification.
# See: Areas/Work/AI-Sessions/Kiro/Probes/2026-07-25-Tripwire-Hook-And-Fixtures-Spec.md §1
#
# STAGED, NOT WIRED as of authoring — do not add to settings.json until the
# Kiro conformance review (spec §4) passes and the user has seen a dry-run.
#
# Flag conditions (any triggers a LOG line; injection requires (a) or (b)):
#   (a) >=3 Edit/Write/NotebookEdit tool_use calls in the final assistant turn
#   (b) >=2 consecutive turns each with >=2 mutating calls (rolling state file)
#   (c) any single Edit/Write whose new content exceeds ~2,000 chars
#       (log-always; does NOT by itself trigger injection)
#
# Response is always observational/non-blocking: never returns a "decision"
# field, only an optional additionalContext reminder, rate-limited to one
# injection per 10 minutes per session.
#
# Kill switch: CONDUCTOR_TRIPWIRE_OFF=1 (exits 0 silently, no log, no state).
# Fail-open: any parse/read error anywhere below → exit 0, no crash, no log.
#
# Test-only override: TRIPWIRE_TEST_TURN_INDEX=<n> selects the n-th turn
# (0-indexed, turns segmented by real user prompts) instead of the transcript's
# actual final turn — lets the acceptance tests target a specific historical
# turn without needing a live Stop event. Never read in production use.

[ "${CONDUCTOR_TRIPWIRE_OFF:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.claude/state"
STATE_FILE="${STATE_DIR}/conductor-tripwire.state"
LOG_FILE="${STATE_DIR}/conductor-tripwire.log"

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

# Everything else happens in python3 for reliable JSONL/JSON handling. The
# whole block is wrapped so ANY failure (bad JSON, missing file, python
# missing, etc.) falls through to a silent, harmless exit 0 — this must never
# block or crash a session.
{
    PY_SCRIPT="${STATE_DIR}/.conductor-tripwire.py.$$"
    cat > "$PY_SCRIPT" <<'PYEOF'
import json, sys, os, re, time

state_file = sys.argv[1]
log_file   = sys.argv[2]

try:
    payload = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)

transcript_path = payload.get("transcript_path", "")
session_id      = payload.get("session_id", "") or "unknown-session"

if not transcript_path or not os.path.isfile(transcript_path):
    sys.exit(0)

try:
    with open(transcript_path, "r", errors="replace") as f:
        lines = f.readlines()
except Exception:
    sys.exit(0)

BASH_MUTATION_RE = re.compile(
    r'(^|[\s;&|])(>>?|mv|cp|rm|sed\s+-i|tee|chmod|git\s+(commit|push|checkout)|mkdir)\b'
)

def is_real_user_entry(d):
    if d.get("type") != "user":
        return False
    content = d.get("message", {}).get("content")
    if isinstance(content, str):
        return True
    if isinstance(content, list):
        types = set(c.get("type") for c in content if isinstance(c, dict))
        if "tool_result" in types and "text" not in types:
            return False
        return True
    return False

# Segment the transcript into "turns": each turn is the run of assistant
# messages between one real user prompt and the next (tool_result-only user
# entries do NOT start a new turn — they're intermediate tool responses within
# the same turn).
turns = []
cur = None
for raw in lines:
    raw = raw.strip()
    if not raw:
        continue
    try:
        d = json.loads(raw)
    except Exception:
        continue
    if is_real_user_entry(d):
        cur = []
        turns.append(cur)
    elif d.get("type") == "assistant":
        if cur is None:
            cur = []
            turns.append(cur)
        cur.append(d)

if not turns:
    sys.exit(0)

test_idx_raw = os.environ.get("TRIPWIRE_TEST_TURN_INDEX", "")
if test_idx_raw != "":
    try:
        idx = int(test_idx_raw)
        if idx < 0 or idx >= len(turns):
            sys.exit(0)
        target_turn = turns[idx]
        turn_label = f"test-idx-{idx}"
    except Exception:
        sys.exit(0)
else:
    target_turn = turns[-1]
    turn_label = "final"

# ---- count tool_use calls in the target turn ----
ewn_count = 0     # Edit/Write/NotebookEdit
bash_mut_count = 0
max_edit_len = 0
tool_counts = {}

for d in target_turn:
    content = d.get("message", {}).get("content", [])
    if not isinstance(content, list):
        continue
    for c in content:
        if not isinstance(c, dict) or c.get("type") != "tool_use":
            continue
        name = c.get("name", "")
        tool_counts[name] = tool_counts.get(name, 0) + 1
        inp = c.get("input", {}) if isinstance(c.get("input"), dict) else {}
        if name in ("Edit", "Write", "NotebookEdit"):
            ewn_count += 1
            s = inp.get("new_string") or inp.get("content") or ""
            if isinstance(s, str):
                max_edit_len = max(max_edit_len, len(s))
        elif name == "Bash":
            cmdtext = inp.get("command", "")
            if isinstance(cmdtext, str) and BASH_MUTATION_RE.search(cmdtext):
                bash_mut_count += 1

mutating_count = ewn_count + bash_mut_count

cond_a = ewn_count >= 3
cond_c = max_edit_len > 2000

# ---- rolling state for condition (b) ----
try:
    with open(state_file) as sf:
        state = json.load(sf)
    if not isinstance(state, dict):
        state = {}
except Exception:
    state = {}

sess_state = state.get(session_id, {}) if isinstance(state.get(session_id), dict) else {}
prev_consec = int(sess_state.get("consec_flagged", 0) or 0)
last_inject_ts = float(sess_state.get("last_inject_ts", 0) or 0)

this_turn_flagged_shape = mutating_count >= 2
new_consec = (prev_consec + 1) if this_turn_flagged_shape else 0
cond_b = new_consec >= 2

sess_state["consec_flagged"] = new_consec

flagged = cond_a or cond_b or cond_c
should_inject = cond_a or cond_b

now = time.time()
did_inject = False
if should_inject:
    if (now - last_inject_ts) >= 600:
        did_inject = True
        sess_state["last_inject_ts"] = now

state[session_id] = sess_state

# Persist state (best-effort; failure here must not crash or block).
try:
    tmp = state_file + ".tmp"
    with open(tmp, "w") as sf:
        json.dump(state, sf)
    os.replace(tmp, state_file)
except Exception:
    pass

if flagged:
    conditions = "".join([
        "a" if cond_a else "",
        "b" if cond_b else "",
        "c" if cond_c else "",
    ])
    ts = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    counts_str = ",".join(f"{k}={v}" for k, v in sorted(tool_counts.items()))
    log_line = (
        f"{ts} | session={session_id} | turn={turn_label} | "
        f"conditions={conditions} | ewn={ewn_count} bash_mut={bash_mut_count} "
        f"consec={new_consec} max_edit_len={max_edit_len} | {counts_str} | "
        f"injected={did_inject}\n"
    )
    try:
        with open(log_file, "a") as lf:
            lf.write(log_line)
    except Exception:
        pass

if did_inject:
    reminder = (
        "[conductor-tripwire] Execution-shaped turn detected ("
        + ",".join([c for c in ["a" if cond_a else "", "b" if cond_b else ""] if c])
        + "). Bright line: original judgment content inline; moving/collating "
        "existing content >~10 lines delegates. If this was user-instructed, "
        "the flag is working as intended."
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "Stop",
            "additionalContext": reminder,
        }
    }))
PYEOF
    out=$(printf '%s' "$input" | python3 "$PY_SCRIPT" "$STATE_FILE" "$LOG_FILE" 2>/dev/null)
    rc=$?
    rm -f "$PY_SCRIPT" 2>/dev/null
    if [ $rc -eq 0 ] && [ -n "$out" ]; then
        printf '%s\n' "$out"
    fi
} || true

exit 0
