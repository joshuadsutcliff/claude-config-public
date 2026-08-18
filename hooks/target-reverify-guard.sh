#!/usr/bin/env bash
# target-reverify-guard.sh — PreToolUse ADVISORY (not a blocker: the user has
# not authorized a new blocker for this rule): re-verify-target-identity
# advisory before a destructive/irreversible command.
#
# Enforces: THE-STANDARD MINE-0007 (data-integrity, critical, 5 incidents).
# Rule: Before any destructive or irreversible operation, independently
# re-verify the target's identity and state via a second signal of a
# different kind (physical check, second data source, explicit enumeration).
#
# Wiring in ~/.claude/settings.json:
#   PreToolUse (matcher: "Bash") → this script
#
# NOTE: This is NOT a blocker. It never emits {"decision":"block"}. It only
# injects additionalContext. Blocking destructive commands is a much higher
# bar than this compile pass covers and would need separate authorization.
#
# Detection: Bash command text matches a narrow destructive-verb pattern list
# (rm -rf, wipe, diskpart, dd ...of=, mkfs, docker rm/rmi, uninstall,
# decommission). Complements (does not replace) destructive-command-guard.sh,
# which warns about USER AUTHORIZATION; this hook warns about TARGET
# IDENTITY re-verification: a distinct failure mode from the incident log
# (misclassified GUID Appx packages, "stale" AD computer objects that were
# live, wrong diskpart disk number).
#
# FAIL-OPEN: any parse error, missing python3, unreadable/unwritable state
# → exit 0 silently. This must never block a command.
#
# Kill switch: TARGET_REVERIFY_GUARD_OFF=1
# Tuning: TARGET_REVERIFY_GUARD_COOLDOWN=120 (seconds, default 120, PER
# NORMALIZED COMMAND: retrying the identical destructive command within the
# window is not re-nudged, but a different destructive command 10 seconds
# later still fires; this is not a single global cooldown).
#
# TEST PROCEDURE (human-run):
#   1. Syntax check:
#        bash -n target-reverify-guard.sh
#   2. Benign command: expect exit 0, no output:
#        echo '{"tool_name":"Bash","tool_input":{"command":"ls -la /tmp"}}' \
#          | bash target-reverify-guard.sh; echo "exit=$?"
#   3. Destructive command: expect exit 0 and a JSON advisory naming
#      MINE-0007 (fresh state):
#        rm -f ~/.claude/state/target-reverify-guard.json
#        echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /home/user/old-vm-backup"}}' \
#          | bash target-reverify-guard.sh; echo "exit=$?"
#   4. Cooldown check: repeat step 3 with the SAME command immediately:
#      expect exit 0, NO output.
#   5. Different destructive command right after: expect exit 0 and a NEW
#      advisory (proves the cooldown is per-command, not global):
#        echo '{"tool_name":"Bash","tool_input":{"command":"docker rm -f old-container"}}' \
#          | bash target-reverify-guard.sh; echo "exit=$?"

[ "${TARGET_REVERIFY_GUARD_OFF:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.claude/state"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE_FILE="${STATE_DIR}/target-reverify-guard.json"
COOLDOWN="${TARGET_REVERIFY_GUARD_COOLDOWN:-120}"

INPUT="$(cat 2>/dev/null)" || exit 0
[ -n "$INPUT" ] || exit 0

python3 - "$INPUT" "$COOLDOWN" "$STATE_FILE" <<'PYEOF' || exit 0
import sys, json, os, re, time, hashlib

try:
    raw = sys.argv[1] if len(sys.argv) > 1 else ""
    cooldown = int(sys.argv[2])
    state_file = sys.argv[3]

    data = json.loads(raw) if raw else {}
    if data.get("tool_name") != "Bash":
        sys.exit(0)

    cmd = (data.get("tool_input", {}) or {}).get("command", "") or ""
    if not cmd.strip():
        sys.exit(0)

    DESTRUCTIVE_PATTERNS = [
        (r"\brm\s+(-[rfRF]+\s+|.*--no-preserve-root)", "recursive/force delete"),
        (r"\bwipe\b", "wipe operation"),
        (r"\bdiskpart\b", "diskpart (disk-level operation)"),
        (r"\bdd\s+.*of=", "raw disk write"),
        (r"\bmkfs\b", "filesystem format"),
        (r"\bdocker\s+(rm|rmi)\b", "docker resource removal"),
        (r"\buninstall\b", "uninstall"),
        (r"\bdecommission\b", "decommission"),
    ]

    findings = [desc for pat, desc in DESTRUCTIVE_PATTERNS if re.search(pat, cmd, re.IGNORECASE)]
    if not findings:
        sys.exit(0)

    norm = re.sub(r"\s+", " ", cmd.strip().lower())
    cmd_hash = hashlib.sha1(norm.encode("utf-8", "replace")).hexdigest()[:16]

    try:
        with open(state_file) as f:
            state = json.load(f)
        if not isinstance(state, dict):
            state = {}
    except Exception:
        state = {}

    now = time.time()
    last = float(state.get(cmd_hash, 0) or 0)
    if now - last < cooldown:
        sys.exit(0)

    state[cmd_hash] = now
    # bound growth: drop entries older than 1 day
    state = {k: v for k, v in state.items() if isinstance(v, (int, float)) and now - v < 86400}
    state[cmd_hash] = now

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

    msg = (
        "[target-reverify-guard / MINE-0007] This command matches a destructive/"
        "irreversible pattern (%s). Before running it: independently re-verify the "
        "TARGET's identity and state via a SECOND signal of a different kind than "
        "whatever identified it (a physical/live check, a second data source, or "
        "explicit enumeration): not just the same query or claim that flagged it. "
        "This is advisory only, not a block; proceed once re-verified."
    ) % "; ".join(findings)

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
