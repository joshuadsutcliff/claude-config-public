#!/usr/bin/env bash
# config-apply-guard.sh — PostToolUse observer: apply-and-verify-live advisory
# after a service-config file is written/edited.
#
# Enforces: THE-STANDARD MINE-0006 (data-integrity, high, 6 incidents).
# Rule: Editing a config file proves nothing about the live system: apply
# the change through the system's own mechanism (docker update, API, reload)
# and verify via the live state/API, never by re-reading the file.
#
# Wiring in ~/.claude/settings.json:
#   PostToolUse (matcher: "Write|Edit") → this script
#
# Detection: the written file's path matches a narrow set of service-config
# shapes (docker-compose.yml, .env, *.conf, *.ini, systemd .service units,
# provisioning/*.yaml, Caddyfile, nginx.conf). Fires only on those paths, not
# on every Write/Edit: arbitrary source/doc files never match.
#
# FAIL-OPEN: any parse error, missing python3, unreadable/unwritable state
# → exit 0 silently. This must never block a write.
#
# Kill switch: CONFIG_APPLY_GUARD_OFF=1
# Tuning: CONFIG_APPLY_GUARD_COOLDOWN=300 (seconds, default 300: a batch of
# related config edits in one turn should nudge once, not once per file)
#
# TEST PROCEDURE (human-run):
#   1. Syntax check:
#        bash -n config-apply-guard.sh
#   2. Benign non-config path: expect exit 0, no output:
#        echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/notes.md","content":"hi"}}' \
#          | bash config-apply-guard.sh; echo "exit=$?"
#   3. Config path: expect exit 0 and a JSON advisory naming MINE-0006:
#        rm -f ~/.claude/state/config-apply-guard.ts
#        echo '{"tool_name":"Edit","tool_input":{"file_path":"/home/user/stack/docker-compose.yml","new_string":"restart: unless-stopped"}}' \
#          | bash config-apply-guard.sh; echo "exit=$?"
#   4. Cooldown check: repeat step 3 immediately: expect exit 0, NO output.

[ "${CONFIG_APPLY_GUARD_OFF:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.claude/state"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE_FILE="${STATE_DIR}/config-apply-guard.ts"
COOLDOWN="${CONFIG_APPLY_GUARD_COOLDOWN:-300}"

INPUT="$(cat 2>/dev/null)" || exit 0
[ -n "$INPUT" ] || exit 0

python3 - "$INPUT" "$COOLDOWN" "$STATE_FILE" <<'PYEOF' || exit 0
import sys, json, os, re, time

try:
    raw = sys.argv[1] if len(sys.argv) > 1 else ""
    cooldown = int(sys.argv[2])
    state_file = sys.argv[3]

    data = json.loads(raw) if raw else {}
    if data.get("tool_name") not in ("Write", "Edit", "NotebookEdit"):
        sys.exit(0)

    tool_input = data.get("tool_input", {}) or {}
    file_path = tool_input.get("file_path", "") or tool_input.get("path", "") or ""
    if not file_path:
        sys.exit(0)

    CONFIG_PATH_RE = re.compile(
        r"(docker-compose\.ya?ml$|/\.env$|\.env\.[a-zA-Z0-9._-]+$|\.conf$|\.ini$|"
        r"\.service$|/systemd/|/provisioning/.*\.ya?ml$|Caddyfile$|nginx\.conf$|"
        r"/etc/.+\.conf$)",
        re.IGNORECASE,
    )
    if not CONFIG_PATH_RE.search(file_path):
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
        "[config-apply-guard / MINE-0006] You just wrote to what looks like a live "
        "service config (%s). The file on disk proves nothing about the running "
        "system. Apply the change through the system's own mechanism (docker update/"
        "recreate, the service's reload API, systemctl daemon-reload + restart) and "
        "verify via LIVE state or API: never by re-reading the file you just wrote."
    ) % file_path

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
