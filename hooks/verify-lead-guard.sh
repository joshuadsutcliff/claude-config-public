#!/usr/bin/env bash
# verify-lead-guard.sh — PostToolUse observer: verify-before-acting advisory
# after a subagent/worker returns.
#
# Enforces: THE-STANDARD MINE-0001 (behavioral, critical, 11 incidents).
# Rule: Treat every subagent factual claim as an unverified lead: confirm
# against filesystem/git/live state with one direct command before acting;
# never accept tool-use or token counters as evidence of work. A worker's
# claim that a tool or dependency is unavailable never authorizes a skipped
# step until the conductor confirms absence with one direct check.
#
# Wiring in ~/.claude/settings.json:
#   PostToolUse (matcher: "Agent|Workflow|TaskOutput") → this script
#
# Detection: reads the completed worker's returned text. Two tiers:
#   (1) UNAVAILABILITY claim (missing tool/dependency/file language): the
#       highest-value, rarest, most damaging pattern per the incident log
#       (5 of 11 incidents were false-negative claims). Short cooldown.
#   (2) Generic worker-return: periodic reminder, long cooldown, so a
#       multi-worker fan-out gets nudged once, not once per worker.
# Async agent launches (status == async_launched) carry no report yet and
# are skipped, same convention as worker-output-size.sh.
#
# FAIL-OPEN: any parse error, missing python3, unreadable/corrupt state,
# or unwritable state dir → exit 0 silently. This must never block a turn.
#
# Kill switch: VERIFY_LEAD_GUARD_OFF=1
# Tuning:
#   VERIFY_LEAD_GUARD_UNAVAIL_COOLDOWN=180   (seconds, default 180)
#   VERIFY_LEAD_GUARD_GENERIC_COOLDOWN=900   (seconds, default 900)
#
# TEST PROCEDURE (human-run):
#   1. Syntax check:
#        bash -n verify-lead-guard.sh
#   2. Benign completed-worker payload (no unavailability language): expect
#      exit 0, and after clearing state, ONE generic advisory JSON line:
#        rm -f ~/.claude/state/verify-lead-guard-generic.ts
#        echo '{"tool_name":"Agent","tool_response":{"content":[{"type":"text","text":"Renamed 6 files."}]}}' \
#          | bash verify-lead-guard.sh; echo "exit=$?"
#   3. Unavailability-claim payload: expect exit 0 and a JSON advisory
#      naming MINE-0001 and the unavailability clause:
#        rm -f ~/.claude/state/verify-lead-guard-unavail.ts
#        echo '{"tool_name":"Agent","tool_response":{"content":[{"type":"text","text":"Playwright is not available on this machine, so I skipped the screenshot."}]}}' \
#          | bash verify-lead-guard.sh; echo "exit=$?"
#   4. Cooldown check: repeat step 3 immediately: expect exit 0, NO output
#      (cooldown suppressing the second injection).
#   5. Async-launch payload: expect exit 0, no output:
#        echo '{"tool_name":"Agent","tool_response":{"status":"async_launched"}}' \
#          | bash verify-lead-guard.sh; echo "exit=$?"

[ "${VERIFY_LEAD_GUARD_OFF:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.claude/state"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

INPUT="$(cat 2>/dev/null)" || exit 0
[ -n "$INPUT" ] || exit 0

UNAVAIL_COOLDOWN="${VERIFY_LEAD_GUARD_UNAVAIL_COOLDOWN:-180}"
GENERIC_COOLDOWN="${VERIFY_LEAD_GUARD_GENERIC_COOLDOWN:-900}"
UNAVAIL_STATE="${STATE_DIR}/verify-lead-guard-unavail.ts"
GENERIC_STATE="${STATE_DIR}/verify-lead-guard-generic.ts"

python3 - "$INPUT" "$UNAVAIL_COOLDOWN" "$GENERIC_COOLDOWN" "$UNAVAIL_STATE" "$GENERIC_STATE" <<'PYEOF' || exit 0
import sys, json, os, re, time

try:
    raw = sys.argv[1] if len(sys.argv) > 1 else ""
    unavail_cd = int(sys.argv[2])
    generic_cd = int(sys.argv[3])
    unavail_state = sys.argv[4]
    generic_state = sys.argv[5]

    data = json.loads(raw) if raw else {}
    if data.get("tool_name") not in ("Agent", "Workflow", "TaskOutput"):
        sys.exit(0)

    resp = data.get("tool_response", data.get("tool_result", ""))
    if isinstance(resp, dict) and resp.get("status") == "async_launched":
        sys.exit(0)

    if isinstance(resp, dict) and isinstance(resp.get("content"), list):
        text = "".join(b.get("text", "") for b in resp["content"] if isinstance(b, dict))
    elif isinstance(resp, str):
        text = resp
    else:
        text = json.dumps(resp) if resp else ""

    if not text.strip():
        sys.exit(0)

    UNAVAIL_RE = re.compile(
        r"\b(not (available|found|installed|present)|doesn.t exist|does not exist|"
        r"cannot find|can.t find|couldn.t (find|locate)|no such (file|tool|dependency)|"
        r"unavailable|missing (dependency|tool)|failed to find|not (supported|possible))\b",
        re.IGNORECASE,
    )

    def cooldown_ok(state_file, cooldown):
        now = time.time()
        try:
            last = float(open(state_file).read().strip())
        except Exception:
            last = 0.0
        if now - last < cooldown:
            return False
        tmp = state_file + f".tmp.{os.getpid()}"
        try:
            with open(tmp, "w") as f:
                f.write(str(now))
            os.replace(tmp, state_file)
        except Exception:
            try:
                os.remove(tmp)
            except Exception:
                pass
        return True

    if UNAVAIL_RE.search(text):
        if not cooldown_ok(unavail_state, unavail_cd):
            sys.exit(0)
        msg = (
            "[verify-lead-guard / MINE-0001] This worker's return contains an "
            "UNAVAILABILITY claim (missing tool/dependency/file). This claim never "
            "authorizes a skipped step on its own: confirm absence yourself with one "
            "direct command (ls / which / cache path / git status) before accepting it "
            "or proceeding as if the step was impossible. 5 of 11 logged MINE-0001 "
            "incidents were false unavailability claims."
        )
    else:
        if not cooldown_ok(generic_state, generic_cd):
            sys.exit(0)
        msg = (
            "[verify-lead-guard / MINE-0001] A worker just returned. Treat its factual "
            "claims as unverified leads, not ground truth: confirm against filesystem/"
            "git/live state with one direct command before acting on them. Tool-use or "
            "token counters are not evidence of work; verify the actual artifact."
        )

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": msg,
        }
    }))
except Exception:
    sys.exit(0)
PYEOF

exit 0
