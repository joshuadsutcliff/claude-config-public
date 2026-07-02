#!/usr/bin/env bash
# post-compact.sh — Claude Code SessionStart hook.
# Fires on every SessionStart, but only injects context when source == "compact"
# (i.e. the conversation was just auto-compacted mid-session). Compaction is the
# field's #1 long-run failure mode: the working state (current goal, files in
# flight, pending tasks) is summarized away and the model silently drifts.
# CLAUDE.md persists across compaction, but live working state does not — so this
# re-injects a deterministic re-grounding instruction. Behavioral guidance only.
#
# Wired in ~/.claude/settings.json under SessionStart (synchronous, so its
# additionalContext reaches the model). Fail-open: any error → no injection.
#
# Disable with POST_COMPACT_OFF=1.

[ "${POST_COMPACT_OFF:-0}" = "1" ] && exit 0

input=$(cat 2>/dev/null) || exit 0

source_val=$(printf '%s' "$input" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('source', ''))
except Exception:
    print('')
" 2>/dev/null)

# Only act when this SessionStart is a post-compaction restart.
[ "$source_val" = "compact" ] || exit 0

read -r -d '' CTX <<'EOF'
[post-compact] The conversation was just compacted — live working state (current goal, files in flight, pending tasks) may have been summarized away, even though CLAUDE.md still applies. Before continuing, RE-GROUND:
1. Restate the current objective and the specific files/changes in flight, in one or two lines.
2. If a plan is active, re-read it (check ~/.claude/plans/ for the current plan file) and the most recent Areas/Work/Session-Logs/ entry if continuing prior work.
3. Re-confirm pending tasks (the open `[ ]` items) before acting.
Core invariants remain in force: end work-completing turns with the quick-recap status line; delegate token-heavy bounded work to sonnet/haiku workers (never inherit the conductor model in subagents); use `git -C <path>`; re-verify any file a subagent cited before acting on it.
EOF

python3 -c "
import json
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'SessionStart',
        'additionalContext': '''$CTX'''
    }
}))
" 2>/dev/null || exit 0
