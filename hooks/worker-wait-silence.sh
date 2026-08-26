#!/usr/bin/env bash
# worker-wait-silence.sh — Claude Code PostToolUse hook (matcher: Agent|Workflow|TaskOutput)
# Suppresses filler narration around worker dispatches.
#
# Problem patterns this hook kills:
#   1. Wait narration: "Waiting on results." / "Worker still running."
#   2. Dispatch announcements: "Dispatched." / "Go received. Dispatching X."
#   3. Intent announcements: "Two issues to handle. Verifying now."
#      (announcing what you're about to do instead of doing it and reporting)
#
# The rule: after a dispatch or worker return, the next user-visible output
# is either a synthesized result, a decision point requiring the user's input,
# or silence. Never a status announcement, never "I'm about to do X."
#
# Kill switch: WORKER_WAIT_SILENCE_OFF=1
# Fail-open: any error exits 0 with no injection.

[ "${WORKER_WAIT_SILENCE_OFF:-0}" = "1" ] && exit 0

echo "[SILENCE] No filler. Do not announce dispatches, do not narrate waits, do not state what you are about to do. Your next user-visible output is either a result (synthesized findings), a decision point (something the user must rule on), or nothing. 'Dispatched.' is filler. 'Go received.' is filler. 'Verifying now.' is filler. Act, then report the outcome."
exit 0
