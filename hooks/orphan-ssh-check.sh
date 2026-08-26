#!/usr/bin/env bash
# orphan-ssh-check.sh — Stop hook.
# At session end, checks for orphaned SSH processes that have been running
# longer than 10 minutes. Reports them as advisory context so the conductor
# (or the user) knows to clean them up.
#
# Also runs as a periodic check: if called via PostToolUse (wired with no
# matcher), it checks every 15 minutes and advises if orphans are found.
# The Stop-hook path always fires; the periodic path is rate-limited.
#
# Purpose: A prior session left several SSH sessions hung unnoticed for
# roughly 48 minutes, consuming TTY resources after their dispatching
# workers had completed.
#
# Adapt the hostname/IP match list below to your own remote hosts, or drop
# the filter entirely to match any long-running ssh process.
#
# Non-blocking. Fail-open.
# Kill switch: ORPHAN_SSH_CHECK_OFF=1

[ "${ORPHAN_SSH_CHECK_OFF:-0}" = "1" ] && exit 0

STATE_DIR="${HOME}/.claude/state"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Find SSH processes older than 10 minutes. Replace this pattern with your
# own remote-host allowlist, or use '[s]sh ' to match any ssh process.
orphans=$(ps -eo pid,etime,command 2>/dev/null | grep -E '[s]sh ' | while read pid etime cmd; do
    # Parse etime: formats are MM:SS, HH:MM:SS, or D-HH:MM:SS
    case "$etime" in
        (*-*) # days: definitely orphaned
            echo "$pid $etime $cmd"
            ;;
        (*:*:*) # HH:MM:SS: check if >= 00:10:00
            hours=$(echo "$etime" | cut -d: -f1)
            mins=$(echo "$etime" | cut -d: -f2)
            if [ "$hours" -gt 0 ] || [ "$mins" -ge 10 ]; then
                echo "$pid $etime $cmd"
            fi
            ;;
        (*:*) # MM:SS: check if >= 10:00
            mins=$(echo "$etime" | cut -d: -f1)
            if [ "$mins" -ge 10 ]; then
                echo "$pid $etime $cmd"
            fi
            ;;
    esac
done 2>/dev/null)

[ -z "$orphans" ] && exit 0

count=$(echo "$orphans" | wc -l | tr -d ' ')
summary=$(echo "$orphans" | head -5 | awk '{print $1, $2, substr($0, index($0,$3), 60)}' | paste -sd '; ' -)

# Rate limit for periodic checks (not Stop hooks)
input=$(cat 2>/dev/null) || true
is_stop=false
if echo "$input" | grep -q '"Stop"' 2>/dev/null; then
    is_stop=true
fi

if [ "$is_stop" = "false" ]; then
    RATE_FILE="${STATE_DIR}/orphan-ssh-last-nudge"
    if [ -f "$RATE_FILE" ]; then
        last=$(cat "$RATE_FILE" 2>/dev/null)
        now=$(date +%s)
        elapsed=$((now - ${last:-0}))
        [ "$elapsed" -lt 900 ] && exit 0  # 15 min cooldown
    fi
    date +%s > "$RATE_FILE" 2>/dev/null
fi

msg="[orphan-ssh-check] ${count} SSH process(es) running longer than 10 minutes: ${summary}. These are likely orphans from completed workers. Consider killing them to free TTY resources."

printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"Stop\",\"additionalContext\":\"${msg}\"}}"

exit 0
