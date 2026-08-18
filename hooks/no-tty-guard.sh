#!/usr/bin/env bash
# no-tty-guard.sh — Two-mode hook (same multi-mode-single-script convention
# as usage-guard.sh):
#   pretool (default): PreToolUse Bash observer
#   stop              : Stop-hook transcript scanner
#
# Enforces: THE-STANDARD MINE-0022 (portability, high, 5 incidents).
# Rule: The agent shell has no TTY or desktop session: use pkexec for
# privileged commands in a graphical session, have the user launch GUI apps
# via `!`, and use run_in_background instead of a bare trailing &. NEVER
# hand the user `!`-prefixed sudo commands, local OR over ssh: the sudo
# password prompt cannot reach them; hand a run-from-a-real-terminal line
# instead.
#
# HOOKABILITY NOTE: the rule has two distinct halves.
#   Half A (mechanical, tool-call-visible): the agent's OWN Bash tool_input
#    : direct `sudo` usage, GUI-launcher + nohup patterns, bare trailing `&`
#     without run_in_background. Covered by `pretool` mode, wired PreToolUse.
#   Half B (mechanical, but only visible in the final assistant TEXT, not any
#     tool payload): the conductor telling the user to run `! sudo ...` or
#     `! ssh ... sudo ...`. This is not a tool call, so PreToolUse/PostToolUse
#     cannot see it: but the Stop hook already reads the transcript directly
#     (see conductor-tripwire.sh's precedent) and CAN regex-scan the final
#     assistant turn's text blocks for this exact string shape. Covered by
#     `stop` mode, wired on the Stop event.
# Both halves are genuinely mechanical/regex-detectable; neither requires
# inferring the model's reasoning.
#
# Wiring in ~/.claude/settings.json:
#   PreToolUse (matcher: "Bash") → bash ~/.claude/hooks/no-tty-guard.sh pretool
#   Stop                          → bash ~/.claude/hooks/no-tty-guard.sh stop
#
# FAIL-OPEN: any parse error, missing python3, unreadable/unwritable state,
# missing transcript → exit 0 silently in both modes.
#
# Kill switch (both modes): NO_TTY_GUARD_OFF=1
# Tuning:
#   NO_TTY_GUARD_PRETOOL_COOLDOWN=60   (seconds, default 60)
#   NO_TTY_GUARD_STOP_COOLDOWN=60      (seconds, default 60)
#
# TEST PROCEDURE (human-run):
#   1. Syntax check:
#        bash -n no-tty-guard.sh
#   2. pretool: benign command: expect exit 0, no output:
#        echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
#          | bash no-tty-guard.sh pretool; echo "exit=$?"
#   3. pretool: direct sudo: expect exit 0 and a JSON advisory:
#        rm -f ~/.claude/state/no-tty-guard-pretool.ts
#        echo '{"tool_name":"Bash","tool_input":{"command":"sudo systemctl restart nginx"}}' \
#          | bash no-tty-guard.sh pretool; echo "exit=$?"
#   4. pretool: bare trailing & without run_in_background: expect exit 0
#      and a JSON advisory (fresh cooldown):
#        rm -f ~/.claude/state/no-tty-guard-pretool.ts
#        echo '{"tool_name":"Bash","tool_input":{"command":"long_running_task.sh &"}}' \
#          | bash no-tty-guard.sh pretool; echo "exit=$?"
#   5. pretool: same but WITH run_in_background true: expect exit 0, no
#      output (proves the flag suppresses the finding):
#        rm -f ~/.claude/state/no-tty-guard-pretool.ts
#        echo '{"tool_name":"Bash","tool_input":{"command":"long_running_task.sh &","run_in_background":true}}' \
#          | bash no-tty-guard.sh pretool; echo "exit=$?"
#   6. stop: needs a real transcript_path; skip if none handy: with a fake
#      minimal JSONL transcript whose assistant text puts the `!`-prefixed
#      command on its OWN line (the realistic shape: this is how Claude
#      Code renders a command-for-the-user block; the detector intentionally
#      requires line-start `!` to avoid false positives on prose that merely
#      mentions "!" mid-sentence), the stop mode should print a JSON advisory:
#        T=$(mktemp)
#        printf '%s\n' '{"type":"user","message":{"content":"do the thing"}}' \
#          '{"type":"assistant","message":{"content":[{"type":"text","text":"Run this:\n! sudo systemctl restart nginx"}]}}' > "$T"
#        rm -f ~/.claude/state/no-tty-guard-stop.ts
#        echo "{\"transcript_path\":\"$T\",\"session_id\":\"test-sess\"}" \
#          | bash no-tty-guard.sh stop; echo "exit=$?"
#        rm -f "$T"

MODE="${1:-pretool}"
[ "${NO_TTY_GUARD_OFF:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.claude/state"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

INPUT="$(cat 2>/dev/null)" || exit 0
[ -n "$INPUT" ] || exit 0

case "$MODE" in

  pretool)
    STATE_FILE="${STATE_DIR}/no-tty-guard-pretool.ts"
    COOLDOWN="${NO_TTY_GUARD_PRETOOL_COOLDOWN:-60}"

    python3 - "$INPUT" "$COOLDOWN" "$STATE_FILE" <<'PYEOF' || exit 0
import sys, json, os, re, time

try:
    raw = sys.argv[1] if len(sys.argv) > 1 else ""
    cooldown = int(sys.argv[2])
    state_file = sys.argv[3]

    data = json.loads(raw) if raw else {}
    if data.get("tool_name") != "Bash":
        sys.exit(0)

    tool_input = data.get("tool_input", {}) or {}
    cmd = tool_input.get("command", "") or ""
    if not cmd.strip():
        sys.exit(0)

    findings = []

    if re.search(r"(^|[\s;&|])sudo\b", cmd):
        findings.append(
            "direct sudo in the agent's own Bash call (no TTY here: the password "
            "prompt cannot be answered; use pkexec sh -c '...' in a graphical session "
            "instead, or hand the user a run-from-a-real-terminal line, never a `!`-prefixed one)"
        )

    GUI_RE = re.compile(
        r"\bnohup\b.*(\.desktop\b|\bxdg-open\b|\bzenity\b|\bkdialog\b|\bfirefox\b|"
        r"\bcode\b|\bsteam\b|\bgtk\b)",
        re.IGNORECASE,
    )
    if GUI_RE.search(cmd):
        findings.append(
            "this looks like a GUI/desktop app launched via nohup: it will fail "
            "silently (no session/DBus). Have the user launch it via `!` instead"
        )

    stripped = cmd.rstrip()
    bare_bg = bool(re.search(r"(?<!&)&\s*$", stripped)) and not stripped.endswith("&&")
    run_in_bg = tool_input.get("run_in_background")
    if bare_bg and run_in_bg is not True:
        findings.append(
            "bare trailing `&` without run_in_background=true: backgrounded jobs get "
            "reaped when the tool's own shell ends; use run_in_background instead"
        )

    if not findings:
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

    msg = "[no-tty-guard / MINE-0022] " + "; ".join(findings) + "."
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": msg,
        }
    }))
except Exception:
    sys.exit(0)
PYEOF
    ;;

  stop)
    STATE_FILE="${STATE_DIR}/no-tty-guard-stop.ts"
    COOLDOWN="${NO_TTY_GUARD_STOP_COOLDOWN:-60}"

    python3 - "$INPUT" "$COOLDOWN" "$STATE_FILE" <<'PYEOF' || exit 0
import sys, json, os, re, time

try:
    raw = sys.argv[1] if len(sys.argv) > 1 else ""
    cooldown = int(sys.argv[2])
    state_file = sys.argv[3]

    payload = json.loads(raw) if raw else {}
    transcript_path = payload.get("transcript_path", "")
    if not transcript_path or not os.path.isfile(transcript_path):
        sys.exit(0)

    with open(transcript_path, "r", errors="replace") as f:
        lines = f.readlines()

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

    turns = []
    cur = None
    for raw_line in lines:
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        try:
            d = json.loads(raw_line)
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

    target_turn = turns[-1]
    text_parts = []
    for d in target_turn:
        content = d.get("message", {}).get("content", [])
        if not isinstance(content, list):
            continue
        for c in content:
            if isinstance(c, dict) and c.get("type") == "text":
                text_parts.append(c.get("text", ""))
    full_text = "\n".join(text_parts)
    if not full_text.strip():
        sys.exit(0)

    BAD_HANDOFF_RE = re.compile(
        r"^\s*!\s*(sudo\b|ssh\b[^\n]{0,120}\bsudo\b)",
        re.IGNORECASE | re.MULTILINE,
    )
    if not BAD_HANDOFF_RE.search(full_text):
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
        "[no-tty-guard / MINE-0022] This turn appears to hand the user a `!`-prefixed "
        "sudo command (local or over ssh). The sudo password prompt cannot reach a "
        "`!`-prefixed command execution path. Replace it with a plain command line "
        "for the user to run from a real terminal, without the `!` prefix."
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "Stop",
            "additionalContext": msg,
        }
    }))
except Exception:
    sys.exit(0)
PYEOF
    ;;

  *)
    exit 0
    ;;
esac

exit 0
