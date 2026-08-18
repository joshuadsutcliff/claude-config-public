#!/usr/bin/env bash
# repeat-dispatch-guard.sh — PreToolUse ADVISORY: repeated-near-identical-
# worker-dispatch detector (two-strike rule).
#
# Enforces: THE-STANDARD MINE-0003 (resilience, high, 7 incidents).
# Rule: On a stalled worker, verify its actual state via files/process
# directly, then TaskStop or resume with an amendment: and after two failed
# worker attempts on the same task, stop dispatching and fix it with one
# bounded direct command.
#
# HOOKABILITY NOTE: "stalled" and "failed" are judgments the hook cannot see
# directly: no tool payload carries a stall/failure flag. What IS mechanical
# and narrow: a near-identical Agent dispatch (same session, same or
# near-literal prompt text) fired a 3rd time is a strong, deterministic proxy
# for "this task keeps not landing" regardless of why. This hook fires on
# THAT proxy, not on stall/fail semantics it cannot observe. This is narrower
# coverage than the full rule (it does not catch "verify via files/process
# directly" as a distinct mechanical check): the injected text carries that
# guidance, but only the repeat-dispatch trigger fires it.
#
# Wiring in ~/.claude/settings.json:
#   PreToolUse (matcher: "Agent") → this script
#
# Detection: normalizes the dispatch prompt (lowercase, collapsed whitespace,
# first 400 chars) and hashes it. Tracks hash occurrences per session_id in a
# rolling REPEAT_DISPATCH_WINDOW. On the 3rd occurrence of the same hash in
# the window, injects the two-strike advisory (rate-limited per hash so it
# doesn't refire on every subsequent retry).
#
# FAIL-OPEN: any parse error, missing python3, unreadable/unwritable state,
# missing session_id → exit 0 silently. This must never block a dispatch.
#
# Kill switch: REPEAT_DISPATCH_GUARD_OFF=1
# Tuning:
#   REPEAT_DISPATCH_GUARD_WINDOW=1200   (seconds, default 20 min)
#   REPEAT_DISPATCH_GUARD_THRESHOLD=3   (occurrences before firing)
#   REPEAT_DISPATCH_GUARD_REFIRE_COOLDOWN=300 (seconds between repeat fires on the same hash)
#
# TEST PROCEDURE (human-run):
#   1. Syntax check:
#        bash -n repeat-dispatch-guard.sh
#   2. Single dispatch: expect exit 0, no output:
#        rm -f ~/.claude/state/repeat-dispatch-guard.json
#        echo '{"session_id":"test-sess","tool_name":"Agent","tool_input":{"prompt":"Fix the flaky test in auth.spec.ts"}}' \
#          | bash repeat-dispatch-guard.sh; echo "exit=$?"
#   3. Same prompt dispatched 2 more times (3rd occurrence should fire):
#        echo '{"session_id":"test-sess","tool_name":"Agent","tool_input":{"prompt":"Fix the flaky test in auth.spec.ts"}}' \
#          | bash repeat-dispatch-guard.sh; echo "exit=$?"
#        echo '{"session_id":"test-sess","tool_name":"Agent","tool_input":{"prompt":"Fix the flaky test in auth.spec.ts"}}' \
#          | bash repeat-dispatch-guard.sh; echo "exit=$?"
#      The 3rd call above should print a JSON advisory naming MINE-0003.
#   4. Different prompt, same session: expect exit 0, no output (fresh hash):
#        echo '{"session_id":"test-sess","tool_name":"Agent","tool_input":{"prompt":"Summarize the README"}}' \
#          | bash repeat-dispatch-guard.sh; echo "exit=$?"

[ "${REPEAT_DISPATCH_GUARD_OFF:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.claude/state"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE_FILE="${STATE_DIR}/repeat-dispatch-guard.json"
WINDOW="${REPEAT_DISPATCH_GUARD_WINDOW:-1200}"
THRESHOLD="${REPEAT_DISPATCH_GUARD_THRESHOLD:-3}"
REFIRE_COOLDOWN="${REPEAT_DISPATCH_GUARD_REFIRE_COOLDOWN:-300}"

INPUT="$(cat 2>/dev/null)" || exit 0
[ -n "$INPUT" ] || exit 0

python3 - "$INPUT" "$WINDOW" "$THRESHOLD" "$REFIRE_COOLDOWN" "$STATE_FILE" <<'PYEOF' || exit 0
import sys, json, os, re, time, hashlib

try:
    raw = sys.argv[1] if len(sys.argv) > 1 else ""
    window = int(sys.argv[2])
    threshold = int(sys.argv[3])
    refire_cooldown = int(sys.argv[4])
    state_file = sys.argv[5]

    data = json.loads(raw) if raw else {}
    if data.get("tool_name") != "Agent":
        sys.exit(0)

    session_id = data.get("session_id", "") or ""
    prompt = (data.get("tool_input", {}) or {}).get("prompt", "") or ""
    if not session_id or not prompt.strip():
        sys.exit(0)

    norm = re.sub(r"\s+", " ", prompt.strip().lower())[:400]
    key = session_id + ":" + hashlib.sha1(norm.encode("utf-8", "replace")).hexdigest()[:16]

    try:
        with open(state_file) as f:
            state = json.load(f)
        if not isinstance(state, dict):
            state = {}
    except Exception:
        state = {}

    now = time.time()
    entry = state.get(key, {}) if isinstance(state.get(key), dict) else {}
    hits = [t for t in entry.get("hits", []) if isinstance(t, (int, float)) and now - t < window]
    hits.append(now)
    entry["hits"] = hits
    last_fired = float(entry.get("last_fired", 0) or 0)

    # prune whole state of stale keys to bound file growth
    state = {
        k: v for k, v in state.items()
        if isinstance(v, dict) and v.get("hits")
        and any(isinstance(t, (int, float)) and now - t < window for t in v["hits"])
    }
    state[key] = entry

    should_fire = len(hits) >= threshold and (now - last_fired >= refire_cooldown)
    if should_fire:
        entry["last_fired"] = now

    tmp = state_file + f".tmp.{os.getpid()}"
    try:
        with open(tmp, "w") as f:
            json.dump(state, f)
        os.replace(tmp, state_file)
    except Exception:
        try:
            os.remove(tmp)
        except Exception:
            pass

    if not should_fire:
        sys.exit(0)

    msg = (
        "[repeat-dispatch-guard / MINE-0003] This near-identical task has now been "
        "dispatched %d times in this session within the last %ds. Per the two-strike "
        "rule: stop dispatching another worker on this task. First verify its actual "
        "state directly (files/process/git: not another worker's report), then either "
        "TaskStop the stuck one, resume it with a bounded amendment, or fix the "
        "remainder yourself with one bounded direct command."
    ) % (len(hits), window)

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": msg,
        }
    }))
except Exception:
    sys.exit(0)
PYEOF

exit 0
