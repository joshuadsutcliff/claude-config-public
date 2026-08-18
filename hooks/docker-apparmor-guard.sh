#!/usr/bin/env bash
# docker-apparmor-guard.sh — PostToolUse observer: AppArmor/PID1-trap
# workaround advisory after a blocked docker stop/restart/kill.
#
# Enforces: THE-STANDARD MINE-0017 (resilience, medium, 5 incidents).
# Rule: When docker stop/restart is AppArmor-blocked or PID1 traps SIGTERM,
# kill the container's PID1 directly (inside for shell containers, host sudo
# kill for distroless) or use the service's internal reload API: never loop
# retries of docker stop.
#
# Wiring in ~/.claude/settings.json:
#   PostToolUse (matcher: "Bash") → this script
#
# Detection: BOTH must hold, so this never fires on a routine, working
# docker stop/restart/kill on a host without AppArmor confinement:
#   (1) the command matched `docker (stop|restart|kill)`
#   (2) the command's own OUTPUT (tool_response) contains a permission/
#       AppArmor failure signal
# This is narrower than a blanket "docker stop ran" match: it only fires on
# the observed failure signature from the incident log.
#
# FAIL-OPEN: any parse error, missing python3, unreadable/unwritable state
# → exit 0 silently. This must never block a command.
#
# Kill switch: DOCKER_APPARMOR_GUARD_OFF=1
# Tuning: DOCKER_APPARMOR_GUARD_COOLDOWN=180 (seconds, default 180)
#
# TEST PROCEDURE (human-run):
#   1. Syntax check:
#        bash -n docker-apparmor-guard.sh
#   2. Successful docker stop (no failure signal in output): expect exit 0,
#      no output:
#        echo '{"tool_name":"Bash","tool_input":{"command":"docker stop myapp"},"tool_response":"myapp"}' \
#          | bash docker-apparmor-guard.sh; echo "exit=$?"
#   3. AppArmor-blocked docker stop: expect exit 0 and a JSON advisory
#      naming MINE-0017:
#        rm -f ~/.claude/state/docker-apparmor-guard.ts
#        echo '{"tool_name":"Bash","tool_input":{"command":"docker restart homarr"},"tool_response":"Error response from daemon: apparmor failed to apply profile: permission denied"}' \
#          | bash docker-apparmor-guard.sh; echo "exit=$?"
#   4. Cooldown check: repeat step 3 immediately: expect exit 0, NO output.
#   5. Non-docker command: expect exit 0, no output:
#        echo '{"tool_name":"Bash","tool_input":{"command":"ls /"},"tool_response":"bin etc"}' \
#          | bash docker-apparmor-guard.sh; echo "exit=$?"

[ "${DOCKER_APPARMOR_GUARD_OFF:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.claude/state"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE_FILE="${STATE_DIR}/docker-apparmor-guard.ts"
COOLDOWN="${DOCKER_APPARMOR_GUARD_COOLDOWN:-180}"

INPUT="$(cat 2>/dev/null)" || exit 0
[ -n "$INPUT" ] || exit 0

python3 - "$INPUT" "$COOLDOWN" "$STATE_FILE" <<'PYEOF' || exit 0
import sys, json, os, re, time

try:
    raw = sys.argv[1] if len(sys.argv) > 1 else ""
    cooldown = int(sys.argv[2])
    state_file = sys.argv[3]

    data = json.loads(raw) if raw else {}
    if data.get("tool_name") != "Bash":
        sys.exit(0)

    cmd = (data.get("tool_input", {}) or {}).get("command", "") or ""
    if not re.search(r"\bdocker\s+(stop|restart|kill)\b", cmd, re.IGNORECASE):
        sys.exit(0)

    resp = data.get("tool_response", data.get("tool_result", ""))
    if isinstance(resp, dict) and isinstance(resp.get("content"), list):
        text = "".join(b.get("text", "") for b in resp["content"] if isinstance(b, dict))
    elif isinstance(resp, str):
        text = resp
    else:
        text = json.dumps(resp) if resp else ""

    if not re.search(r"apparmor|permission denied|operation not permitted", text, re.IGNORECASE):
        sys.exit(0)

    now = time.time()
    try:
        last = float(open(state_file).read().strip())
    except Exception:
        last = 0.0
    if now - last < cooldown:
        sys.exit(0)
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

    msg = (
        "[docker-apparmor-guard / MINE-0017] That docker stop/restart/kill just failed "
        "with an AppArmor/permission signature. Do NOT loop retrying docker stop: it "
        "will keep failing. Instead: for shell containers, kill the container's PID1 "
        "directly from inside (docker exec <c> kill 1, or the appropriate signal if "
        "PID1 traps SIGTERM); for distroless/host-level, use host sudo kill on the "
        "container's PID1; or use the service's own internal reload/restart API "
        "instead of the docker CLI verb."
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
