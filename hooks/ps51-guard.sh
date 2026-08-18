#!/usr/bin/env bash
# ps51-guard.sh — PostToolUse observer: PowerShell 5.1 defensive-scripting
# advisory on .ps1 writes/edits.
#
# Enforces: THE-STANDARD MINE-0024 (portability, medium, 5 incidents; scoped
# 2026-08-17 to Windows/PowerShell remote-administration targets, enforcement
# unchanged).
# Rule: Target PowerShell 5.1 defensively: ASCII-only deployed scripts,
# statement-form try/catch with assignment inside branches, never trust
# (var).Count for null checks, and judge native-command success by stdout +
# $LASTEXITCODE.
#
# HOOKABILITY NOTE: of the four sub-clauses, two are cleanly regex-detectable
# in the WRITTEN CONTENT with low false-positive risk:
#   (1) non-ASCII bytes in a .ps1 file (the em-dash/UTF-8-vs-cp1252 trap)
#   (2) `$x = try { ... } catch { ... }`: inline try/catch-as-expression,
#       invalid syntax in PS 5.1
# The other two ("(var).Count is unreliable", "$LASTEXITCODE over exit code")
# are judgment calls about DATA FLOW, not static-detectable in file text
# without false positives (e.g. `.Count` is used correctly constantly): NOT
# covered by pattern-matching here; the injected message still NAMES them as
# a reminder, but they do not gate whether this hook fires.
#
# Wiring in ~/.claude/settings.json:
#   PostToolUse (matcher: "Write|Edit") → this script
#
# FAIL-OPEN: any parse error, missing python3, unreadable/unwritable state
# → exit 0 silently. This must never block a write.
#
# Kill switch: PS51_GUARD_OFF=1
# Tuning: PS51_GUARD_COOLDOWN=300 (seconds, default 300)
#
# TEST PROCEDURE (human-run):
#   1. Syntax check:
#        bash -n ps51-guard.sh
#   2. Non-.ps1 file: expect exit 0, no output:
#        echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/notes.md","content":"hi"}}' \
#          | bash ps51-guard.sh; echo "exit=$?"
#   3. Clean ASCII .ps1 with statement-form try/catch: expect exit 0, no
#      output. NOTE: use a forward-slash path in test payloads (not a
#      Windows backslash path): zsh's `echo` collapses `\\` before it
#      reaches python's JSON parser and corrupts the escaping; the hook
#      itself handles real backslash-path JSON fine, this is a test-harness
#      artifact only:
#        echo '{"tool_name":"Write","tool_input":{"file_path":"/scripts/deploy.ps1","content":"try { Get-Service } catch { Write-Host $_ }"}}' \
#          | bash ps51-guard.sh; echo "exit=$?"
#   4. .ps1 with inline try/catch assignment: expect exit 0 and a JSON
#      advisory naming MINE-0024:
#        rm -f ~/.claude/state/ps51-guard.ts
#        echo '{"tool_name":"Write","tool_input":{"file_path":"/scripts/deploy.ps1","content":"$x = try { Get-Service } catch { $null }"}}' \
#          | bash ps51-guard.sh; echo "exit=$?"
#   5. Cooldown check: repeat step 4 immediately: expect exit 0, NO output.

[ "${PS51_GUARD_OFF:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.claude/state"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE_FILE="${STATE_DIR}/ps51-guard.ts"
COOLDOWN="${PS51_GUARD_COOLDOWN:-300}"

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
    if not re.search(r"\.ps1$", file_path, re.IGNORECASE):
        sys.exit(0)

    content = ""
    for k in ("content", "new_string", "new_str", "text"):
        if k in tool_input and isinstance(tool_input[k], str):
            content = tool_input[k]
            break
    if not content:
        sys.exit(0)

    findings = []
    if any(ord(c) > 127 for c in content):
        findings.append(
            "contains non-ASCII characters (em-dashes/curly quotes mangle to cp1252 "
            "on PS 5.1 deploy targets: keep deployed scripts ASCII-only)"
        )
    if re.search(r"[=(]\s*try\s*\{", content):
        findings.append(
            "appears to use try/catch as an inline expression (`$x = try {...} "
            "catch {...}`): invalid in PS 5.1; use statement-form try/catch with the "
            "assignment inside each branch instead"
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

    msg = (
        "[ps51-guard / MINE-0024] %s: this .ps1 file: %s. Also remember (not "
        "pattern-checked here): never trust (var).Count for null checks on PS 5.1 "
        "(@($null).Count == 1), and judge native-command success by stdout + "
        "$LASTEXITCODE, not by the presence of stderr text."
    ) % (file_path, "; ".join(findings))

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
