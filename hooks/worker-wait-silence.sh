#!/usr/bin/env bash
# worker-wait-silence.sh — Claude Code PostToolUse hook (matcher: Agent|Workflow|TaskOutput)
# Injects a silence instruction after every worker dispatch, so the conductor
# does not narrate the wait with filler status messages.
#
# Problem: The conductor model fills dead air between dispatch and worker return with progress
# narration ("Waiting on results." / "Worker still running." / "I'll wait for
# the completion notifications.") that adds no value and clutters the output.
#
# Solution: inject a constraint immediately after each dispatch. The model sees
# it before producing its next output token.
#
# Kill switch: WORKER_WAIT_SILENCE_OFF=1
# Fail-open: any error exits 0 with no injection.

[ "${WORKER_WAIT_SILENCE_OFF:-0}" = "1" ] && exit 0

echo "[WORKER DISPATCH COMPLETE] Wait silently. Do not narrate the wait, do not report worker status, do not produce filler messages while workers run. Your next output is the synthesized result after workers return. If multiple workers are outstanding, wait for all of them before producing output unless one returns information that changes the plan."
exit 0
