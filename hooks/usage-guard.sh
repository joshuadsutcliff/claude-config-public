#!/usr/bin/env bash
# usage-guard.sh — Claude Code hook: usage-cap enforcement + conductor-model policy
# Four modes: pct | block | inform | refresh
#
# Conductor = role, not a fixed model. Policy 1 denies any subagent that does not
# EXPLICITLY specify sonnet/haiku (the enforced default for token-efficiency),
# an explicit opus (deliberate heavy delegation per CLAUDE.md rule 12), or a
# pinned cheap worker. Unspecified/inherited models are always denied.
# This enforces the efficient-conductor delegation design mechanically.
# (2026-07-12: explicit opus allowed by owner decision; was previously denied.)
#
# auto-burn-check (2026-07-24): on the block-mode ALLOW path (no deny policy fired),
# inject the current burn signal + routing band into the model's context via
# PreToolUse additionalContext, cooldown-gated, so a fan-out never happens blind.
#
# USAGE SOURCE (2026-09-03, Claude Code: rewired off the retired external
# cost-proxy tool onto the statusline JSON cache, per the Kiro usage-guard-rewire
# design). The guard no longer estimates anything and no longer touches the
# network. It reads Claude Code's REAL metered rate-limit percentages out of a
# local JSON cache written by hooks/statusline-usage.sh (Job A3):
#   ${USAGE_GUARD_USAGE_FILE:-~/.claude/state/claude-usage.json}
#   { five_hour, five_hour_resets_at, seven_day, seven_day_resets_at,
#     fable_weekly, context, captured_at }
# Percentages are integers; fable_weekly/context may be JSON null. A read that is
# missing, unparseable, or older than USAGE_GUARD_USAGE_MAX_AGE yields -1 on the
# affected dimensions, and -1 NEVER blocks: the usage layer is fail-open,
# absolutely. (`context` is read by the statusline only; the guard ignores it.)
#
# Wired in ~/.claude/settings.json:
#   SessionStart   → refresh (retained no-op; the statusline hook owns the cache)
#   UserPromptSubmit → inform
#   PreToolUse Agent|Workflow → block

MODE="${1:-block}"

# ---- usage source (2026-09-03, Claude Code, per Kiro usage-guard-rewire design) ----
# The SOLE input to the usage layer. Written by hooks/statusline-usage.sh; this
# script only ever READS it, never writes it. MAX_AGE is deliberately generous
# (1h): the writer refreshes at most every 30s while a session is live, so a file
# older than an hour means no session has been active recently and the numbers are
# not worth gating on. Past that age we go -1 (unavailable) rather than act on
# stale data: being blind and fail-open is safer than being confidently wrong.
USAGE_FILE="${USAGE_GUARD_USAGE_FILE:-${HOME}/.claude/state/claude-usage.json}"
USAGE_MAX_AGE="${USAGE_GUARD_USAGE_MAX_AGE:-3600}"

# Hard-block thresholds, one per dimension. five_hour and seven_day are GENERAL
# windows: either one at/over its own threshold stops ALL delegation (Policy 2).
# fable_weekly is a DISPATCH-SCOPED quota: it gates only Agent calls whose model
# is literally "fable" (Policy 2.5) and must never stop a sonnet/haiku/opus worker
# or a Workflow, because those draw on entirely different budgets.
BLOCK_PCT="${USAGE_GUARD_BLOCK_PCT:-90}"
BLOCK_PCT_7D="${USAGE_GUARD_BLOCK_PCT_7D:-90}"
BLOCK_PCT_FABLE="${USAGE_GUARD_BLOCK_PCT_FABLE:-90}"
WARN_PCT="${USAGE_GUARD_WARN_PCT:-70}"
CHEAP_WORKERS="researcher|code-generator|tester|code-reviewer"

# auto-burn-check: cooldown between context injections on the block ALLOW path,
# and the state file tracking the last injection time. USAGE_GUARD_BURNCHECK_OFF=1
# disables the whole feature (silent allow), same convention as other *_OFF vars.
BURNCHECK_COOLDOWN="${USAGE_GUARD_BURNCHECK_COOLDOWN:-120}"
BURNCHECK_STATE_FILE="${HOME}/.cache/claude-usage-guard-burncheck.ts"
# An unavailable signal is rare and persistent: a much longer, separate cooldown
# keeps that alarm from repeating at every normal-band interval. (2026-09-03: with
# the external tool gone there is no refresh to attempt and no failure to
# distinguish, so "unavailable" now means exactly one thing: the local usage
# cache is missing, unreadable, or stale.)
BURNCHECK_DEGRADED_COOLDOWN="${USAGE_GUARD_BURNCHECK_DEGRADED_COOLDOWN:-900}"
BURNCHECK_DEGRADED_STATE_FILE="${HOME}/.cache/claude-usage-guard-burncheck-degraded.ts"


# M1 spawn-rate limiter (2026-07-26, Kiro battery postmortem — mechanical control).
# Hard-denies Agent/Workflow spawns beyond SPAWN_RATE_MAX within a rolling
# SPAWN_RATE_WINDOW. The log is MACHINE-GLOBAL (not per-session): burst
# parallelism across concurrent sessions is exactly the failure mode the pct
# proxy cannot see. Override for an explicitly owner-authorized burst:
# SPAWN_RATE_OVERRIDE=1 (per-session env var, never set by the model).
SPAWN_RATE_MAX="${USAGE_GUARD_SPAWN_RATE_MAX:-4}"
SPAWN_RATE_WINDOW="${USAGE_GUARD_SPAWN_RATE_WINDOW:-300}"
SPAWN_RATE_LOG="${HOME}/.cache/claude-spawn-rate.log"

# ---------- usage read (2026-09-03, Claude Code: replaces the old pair of
# external-tool refresh + cached-percentage reader, per the Kiro
# usage-guard-rewire design) ----------
# Sets U_5H / U_7D / U_FABLE from $USAGE_FILE. Each is an integer percentage, or
# -1 meaning "unavailable" (the same sentinel the old cached reader used), so every
# existing "-1 never blocks" comparison still reads naturally.
#
# FAIL-OPEN IS ABSOLUTE. Missing file, unreadable file, empty file, invalid JSON,
# missing keys, non-integer values, an absent/non-numeric captured_at, a
# captured_at in the future (clock skew), an age past USAGE_MAX_AGE, or no python3
# on the box at all → all three go -1. This function never errors, never exits
# non-zero, and never puts anything on stdout beyond the three values its own
# caller consumes. A JSON null on fable_weekly poisons ONLY fable_weekly; the
# general windows stay usable, because one dispatch-scoped quota going dark is no
# reason to blind the cap gate.
#
# No network, no npx, no subprocess other than python3. A local file read cannot
# hang, which is why the old bounded self-heal/timeout machinery is gone entirely.
read_usage() {
    U_5H=-1
    U_7D=-1
    U_FABLE=-1

    _ru_out=$(python3 - "$USAGE_FILE" "$USAGE_MAX_AGE" 2>/dev/null <<'PYEOF'
import sys, json, time

def as_int(v):
    # JSON null, strings, bools, anything unexpected -> -1 for THAT dimension only.
    if isinstance(v, bool):
        return -1
    if isinstance(v, int):
        return v
    if isinstance(v, float):
        return int(round(v))
    return -1

five = seven = fable = -1
try:
    try:
        max_age = int(float(sys.argv[2]))
    except Exception:
        max_age = 3600
    with open(sys.argv[1]) as f:
        d = json.load(f)
    if not isinstance(d, dict):
        raise ValueError('not a JSON object')
    cap = d.get('captured_at')
    if isinstance(cap, bool) or not isinstance(cap, (int, float)):
        raise ValueError('captured_at missing or non-numeric')
    age = int(time.time()) - int(cap)
    if age < 0 or age > max_age:
        raise ValueError('stale, or future-dated by clock skew')
    five  = as_int(d.get('five_hour'))
    seven = as_int(d.get('seven_day'))
    fable = as_int(d.get('fable_weekly'))
except Exception:
    five = seven = fable = -1

print('%d %d %d' % (five, seven, fable))
PYEOF
    ) || _ru_out=""

    # Shape-check before splitting: python3 absent gives an empty string, and
    # anything that is not digits/spaces/minus is discarded wholesale.
    case "$_ru_out" in
        ''|*[!0-9\ -]*) _ru_out="" ;;
    esac
    if [ -n "$_ru_out" ]; then
        # set -- inside a function rebinds only the FUNCTION's positional params.
        set -- $_ru_out
        U_5H="${1:--1}"
        U_7D="${2:--1}"
        U_FABLE="${3:--1}"
    fi

    # Final numeric sanity: a non-numeric value must degrade to -1, never error.
    [ "$U_5H"    -eq "$U_5H"    ] 2>/dev/null || U_5H=-1
    [ "$U_7D"    -eq "$U_7D"    ] 2>/dev/null || U_7D=-1
    [ "$U_FABLE" -eq "$U_FABLE" ] 2>/dev/null || U_FABLE=-1
    # Collapse any negative value onto the single -1 sentinel.
    [ "$U_5H"    -lt 0 ] 2>/dev/null && U_5H=-1
    [ "$U_7D"    -lt 0 ] 2>/dev/null && U_7D=-1
    [ "$U_FABLE" -lt 0 ] 2>/dev/null && U_FABLE=-1
    return 0
}

# ---------- max of the two GENERAL windows (2026-09-03, Claude Code) ----------
# Ignores -1 dimensions; prints -1 only when BOTH are unavailable. fable_weekly is
# deliberately not an input: it is a dispatch-scoped quota, not a general burn
# signal, and must never move the routing band or the pct contract.
usage_max() {
    _um_a="$1"
    _um_b="$2"
    _um_m=-1
    if [ "$_um_a" -ge 0 ] 2>/dev/null; then
        _um_m="$_um_a"
    fi
    if [ "$_um_b" -ge 0 ] 2>/dev/null && [ "$_um_b" -gt "$_um_m" ] 2>/dev/null; then
        _um_m="$_um_b"
    fi
    echo "$_um_m"
}

# ---------- modes ----------
case "$MODE" in

  pct)
    # Contract (relied on by ~/.claude/commands/goal.md for goal-loop stop
    # conditions): a single integer on stdout, nothing else, exit 0. Prints the
    # max of the two general windows, or -1 when neither is available.
    # (2026-09-03: the old self-heal refresh retry is gone. There is nothing left
    # to refresh, and a -1 here now means the cache itself is missing or stale.)
    read_usage
    usage_max "$U_5H" "$U_7D"
    ;;

  refresh)
    # Retained no-op (2026-09-03, Claude Code, per Kiro usage-guard-rewire design).
    # hooks/statusline-usage.sh is now the SOLE writer of the usage cache, so this
    # guard has nothing to refresh and does no work here. The arm is kept only
    # because settings.json still wires it at SessionStart, and an unrecognised
    # mode falls through to the *) arm below, which exits 1 with a stderr message.
    # Explicit success instead of an accidental error on every session start.
    exit 0
    ;;

  inform)
    # (2026-09-03, Claude Code: reads the metered percentages; the old degraded
    # marker and the cost-cap/approximation language are gone with the estimator.)
    read_usage
    i_pct=$(usage_max "$U_5H" "$U_7D")
    if [ "$i_pct" -ge "$WARN_PCT" ] 2>/dev/null; then
        i_dim="7-day"
        if [ "$U_5H" -ge 0 ] 2>/dev/null && [ "$U_5H" = "$i_pct" ]; then
            i_dim="5-hour"
        fi
        cat <<EOF
[usage-guard] WARNING: ${i_dim} usage window at ${i_pct}% (warn at ${WARN_PCT}%; hard block at ${BLOCK_PCT}% 5-hour / ${BLOCK_PCT_7D}% 7-day).
This is Claude Code's own metered rate-limit percentage, not an estimate. Prefer small waves near the cap.
EOF
    fi
    ;;

  block)
    input=$(cat)
    tool_name=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('tool_name',''))" "$input" 2>/dev/null)

    # ---- Policy 1: deny conductor-model subagents (always enforced, regardless of usage) ----
    if [ "$tool_name" = "Agent" ]; then
        model=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get('tool_input', {}).get('model', ''))
" "$input" 2>/dev/null)

        subagent_type=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d.get('tool_input', {}).get('subagent_type', ''))
" "$input" 2>/dev/null)

        is_allowed=false
        case "$model" in
            sonnet|haiku) is_allowed=true ;;
            opus) is_allowed=true ;;  # explicit opt-in only: deliberate heavy delegation (CLAUDE.md rule 12)
            fable) is_allowed=true ;;  # explicit opt-in: frontier worker, 2026-08-28 (Fable-as-worker capability)
        esac
        if echo "$subagent_type" | grep -qE "^($CHEAP_WORKERS)$"; then
            is_allowed=true
        fi

        if ! $is_allowed; then
            python3 -c "
import json
print(json.dumps({
    'decision': 'block',
    'reason': (
        'Conductor-model subagent denied. '
        'Agent calls must specify model explicitly: \"sonnet\" or \"haiku\" (the token-efficient default), '
        '\"opus\" only for deliberate heavy delegation (deep reviews, gnarly debugging), '
        '\"fable\" only for deliberate frontier-tier delegation (explicit opt-in, never inherited), '
        'or use a pinned cheap worker via subagent_type (researcher / code-generator / tester / code-reviewer). '
        'Unspecified models inherit the conductor and are always denied — '
        'the conductor/manager model runs in the main loop only. '
        'Re-issue with an explicit model or named worker.'
    )
}))"
            exit 0
        fi
    fi

    # Fable worker rate cap: deferred, revisit if Fable workers become routine (2026-08-28)
    # ---- Policy 1.5: opus worker cap — max 1 opus worker per dispatch round (2026-08-15, Kiro analysis) ----
    # The parallel ceiling (4 workers/round) is model-agnostic. Without this gate,
    # the conductor could rationalize spawning 4 opus workers ("reasoning-heavy") in
    # a single round. This policy mechanically limits opus-model workers to 1 per
    # rolling window (aligned with iteration-cap's 60s round debounce). Additional
    # opus workers within the same window are blocked with a clear re-route message.
    # Override: OPUS_WORKER_CAP_OVERRIDE=1 (the owner sets this manually for an explicit burst).
    # Fail-open: log read failure or corrupt file → treated as 0 recent opus spawns.
    if [ "$tool_name" = "Agent" ] && [ "$model" = "opus" ] && [ "${OPUS_WORKER_CAP_OVERRIDE:-0}" != "1" ]; then
        OPUS_RATE_WINDOW="${USAGE_GUARD_OPUS_RATE_WINDOW:-60}"
        OPUS_RATE_MAX="${USAGE_GUARD_OPUS_RATE_MAX:-1}"
        OPUS_RATE_LOG="${HOME}/.cache/claude-opus-worker-rate.log"
        mkdir -p "$(dirname "$OPUS_RATE_LOG")" 2>/dev/null

        or_now=$(date +%s)
        or_cutoff=$(( or_now - OPUS_RATE_WINDOW ))
        or_recent=0
        if [ -f "$OPUS_RATE_LOG" ]; then
            or_kept=$(awk -v c="$or_cutoff" '$1 >= c' "$OPUS_RATE_LOG" 2>/dev/null)
            if [ -n "$or_kept" ]; then
                { printf '%s\n' "$or_kept" > "$OPUS_RATE_LOG"; } 2>/dev/null
                or_recent=$(printf '%s\n' "$or_kept" | grep -c '^[0-9]' 2>/dev/null)
            else
                { : > "$OPUS_RATE_LOG"; } 2>/dev/null
            fi
            case "$or_recent" in ''|*[!0-9]*) or_recent=0 ;; esac
        fi
        if [ "$or_recent" -ge "$OPUS_RATE_MAX" ] 2>/dev/null; then
            python3 -c "
import json, sys
n, mx, win = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    'decision': 'block',
    'reason': (
        f'Opus worker cap: {n} opus-model worker(s) already dispatched in the last {win}s '
        f'(max {mx} per dispatch round). This prevents the conductor from rationalizing '
        'multiple expensive opus workers when sonnet/haiku would suffice. '
        'Re-route the remaining workers to model: \"sonnet\" (or \"haiku\" for mechanical tasks). '
        'If this task genuinely needs multiple opus workers, the owner sets '
        'OPUS_WORKER_CAP_OVERRIDE=1 himself.'
    )
}))" "$or_recent" "$OPUS_RATE_MAX" "$OPUS_RATE_WINDOW" 2>/dev/null
            exit 0
        fi
        { echo "$or_now" >> "$OPUS_RATE_LOG"; } 2>/dev/null
    fi

    # ---- usage read + test harness (2026-09-03, Claude Code: rewired off the
    # retired external cost-proxy tool onto the statusline JSON cache, per the
    # Kiro usage-guard-rewire design) ----
    # Resolved ONCE here and reused by Policy 2, Policy 2.5 and Policy 4, so the
    # three gates can never disagree about what the numbers were on this dispatch.
    #
    # Test harness: active only when USAGE_GUARD_TEST_MODE=1 AND at least one of
    # the three fake vars is set. Each dimension is independently fakeable, and an
    # UNSET fake dimension reads 0 (fresh/idle), NOT the real cache value and NOT
    # -1. That is what lets one dimension be exercised in isolation without the
    # live numbers leaking into the test. With USAGE_GUARD_TEST_MODE unset, no
    # test-mode code path executes at all and behaviour is a plain cache read.
    ug_test_mode=0
    if [ "${USAGE_GUARD_TEST_MODE:-0}" = "1" ] && { [ -n "${USAGE_GUARD_FAKE_PCT:-}" ] || [ -n "${USAGE_GUARD_FAKE_PCT_7D:-}" ] || [ -n "${USAGE_GUARD_FAKE_PCT_FABLE:-}" ]; }; then
        ug_test_mode=1
        U_5H="${USAGE_GUARD_FAKE_PCT:-0}"
        U_7D="${USAGE_GUARD_FAKE_PCT_7D:-0}"
        U_FABLE="${USAGE_GUARD_FAKE_PCT_FABLE:-0}"
    else
        read_usage
    fi

    # ---- Policy 2: usage cap gate for general windows (5-hour AND 7-day) ----
    # Either general window at/over its own threshold stops delegation. These are
    # real metered percentages now, not a cost proxy, so the number quoted in the
    # deny text is the same number Claude Code's /usage reports.
    # -1 (unavailable) NEVER blocks: every comparison is guarded on ">= 0" first,
    # and each test is 2>/dev/null so a junk threshold env var fails the test
    # rather than erroring its way into a deny. The guard must not brick
    # delegation on its own bookkeeping.
    p2_trip_5h=0
    p2_trip_7d=0
    if [ "$U_5H" -ge 0 ] 2>/dev/null && [ "$U_5H" -ge "$BLOCK_PCT" ] 2>/dev/null; then
        p2_trip_5h=1
    fi
    if [ "$U_7D" -ge 0 ] 2>/dev/null && [ "$U_7D" -ge "$BLOCK_PCT_7D" ] 2>/dev/null; then
        p2_trip_7d=1
    fi
    if [ "$p2_trip_5h" = "1" ] || [ "$p2_trip_7d" = "1" ]; then
        python3 -c "
import json, sys
h5, d7, b5, b7 = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
t5, t7 = sys.argv[5] == '1', sys.argv[6] == '1'
prefix = '[TEST-MODE] ' if sys.argv[7] == '1' else ''
tripped = []
if t5:
    tripped.append(f'5-hour window at {h5}% (block threshold {b5}%)')
if t7:
    tripped.append(f'7-day window at {d7}% (block threshold {b7}%)')
if len(tripped) == 2:
    head = 'Usage cap gate: BOTH general windows are over threshold: ' + '; '.join(tripped) + '. '
else:
    head = 'Usage cap gate: ' + tripped[0] + '. '
print(json.dumps({
    'decision': 'block',
    'reason': (
        prefix + head +
        'Pause delegation and resume when the window clears. '
        'Run: bash ~/.claude/hooks/usage-guard.sh pct to check the current level. '
        'Do NOT absorb delegation work into the main loop — wait and re-dispatch.'
    )
}))" "$U_5H" "$U_7D" "$BLOCK_PCT" "$BLOCK_PCT_7D" "$p2_trip_5h" "$p2_trip_7d" "$ug_test_mode"
        exit 0
    fi

    # ---- Policy 2.5: Fable weekly quota gate (2026-09-03, Claude Code, per Kiro
    # usage-guard-rewire design) ----
    # SCOPE IS THE WHOLE POINT. This fires ONLY for an Agent dispatch whose model
    # is literally "fable". Fable draws on its own weekly quota; a saturated Fable
    # quota says nothing about sonnet/haiku/opus headroom, so it must never stop
    # those workers and must never touch a Workflow call. The remedy is therefore
    # RE-ROUTE THIS ONE WORKER, not "pause delegation": that is Policy 2's job,
    # and conflating the two would strand the conductor with nowhere to send work.
    # $model is set inside Policy 1's tool_name = Agent branch above and persists
    # (the same bash-variable-persistence precedent Policy 1.5 relies on). It is
    # empty when tool_name is not Agent, which the model = fable test excludes.
    # -1 (unavailable) NEVER blocks.
    if [ "$tool_name" = "Agent" ] && [ "$model" = "fable" ]; then
        p25_trip=0
        if [ "$U_FABLE" -ge 0 ] 2>/dev/null && [ "$U_FABLE" -ge "$BLOCK_PCT_FABLE" ] 2>/dev/null; then
            p25_trip=1
        fi
        if [ "$p25_trip" = "1" ]; then
            python3 -c "
import json, sys
pct, thr = sys.argv[1], sys.argv[2]
prefix = '[TEST-MODE] ' if sys.argv[3] == '1' else ''
print(json.dumps({
    'decision': 'block',
    'reason': (
        prefix +
        f'Fable weekly quota gate: the Fable 7-day quota is at {pct}% '
        f'(block threshold {thr}%). This gate is scoped to THIS worker only: '
        'sonnet, haiku and opus draw on separate budgets and are unaffected. '
        'Re-issue this same dispatch with model: \"sonnet\" (or \"haiku\" for '
        'mechanical work, \"opus\" if it is genuinely reasoning-heavy). '
        'Do NOT pause delegation overall and do NOT absorb the work into the '
        'main loop: only the Fable routing choice is blocked. '
        'Run: bash ~/.claude/hooks/usage-guard.sh pct for the general windows.'
    )
}))" "$U_FABLE" "$BLOCK_PCT_FABLE" "$ug_test_mode"
            exit 0
        fi
    fi

    # ---- Policy 3: gh-auth mutex — REMOVED 2026-08-26 (single-account consolidation) ----
    # This policy previously created a 10-minute lock (~/.claude/locks/gh-auth.lock)
    # and DENIED any Agent/Workflow spawn whose prompt touched `gh auth switch|login`
    # while another such spawn's lock was still fresh. It existed because gh's active
    # account is machine-global and two concurrent account-switching workers could race.
    # The setup consolidated onto a single GitHub account; the second account is
    # deprecated. With only one account there is nothing to switch between and no race
    # to guard against, so the lock/deny mechanic is disabled. The purely advisory
    # reminder in gh-auth-guard.sh (a separate hook, unchanged) is kept.

    # ---- Policy 3.5: M1 hard spawn-rate limiter (2026-07-26, Kiro battery postmortem) ----
    # Runs AFTER the other deny policies so only spawns that would actually proceed
    # are counted. Denied attempts are NOT appended to the log, so retrying a denied
    # spawn cannot extend the lockout. Semantics: at most SPAWN_RATE_MAX allowed
    # spawns per rolling SPAWN_RATE_WINDOW, machine-global. A corrupt/unreadable
    # log fails OPEN (treated as empty) — the limiter must never brick delegation
    # on its own bookkeeping.
    if [ "${SPAWN_RATE_OVERRIDE:-0}" != "1" ] && { [ "$tool_name" = "Agent" ] || [ "$tool_name" = "Workflow" ]; }; then
        sr_now=$(date +%s)
        sr_cutoff=$(( sr_now - SPAWN_RATE_WINDOW ))
        sr_recent=0
        if [ -f "$SPAWN_RATE_LOG" ]; then
            # Prune to in-window entries (also bounds file growth forever).
            sr_kept=$(awk -v c="$sr_cutoff" '$1 >= c' "$SPAWN_RATE_LOG" 2>/dev/null)
            if [ -n "$sr_kept" ]; then
                { printf '%s\n' "$sr_kept" > "$SPAWN_RATE_LOG"; } 2>/dev/null
                sr_recent=$(printf '%s\n' "$sr_kept" | grep -c '^[0-9]' 2>/dev/null)
            else
                { : > "$SPAWN_RATE_LOG"; } 2>/dev/null
            fi
            case "$sr_recent" in ''|*[!0-9]*) sr_recent=0 ;; esac
        fi
        if [ "$sr_recent" -ge "$SPAWN_RATE_MAX" ] 2>/dev/null; then
            python3 -c "
import json, sys
n, mx, win = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    'decision': 'block',
    'reason': (
        f'M1 spawn-rate limiter: {n} agent/workflow spawns already allowed in the last {win}s '
        f'(max {mx}, machine-global across ALL sessions). This is a mechanical circuit breaker '
        'from the 2026-07-25 battery postmortem — it does not negotiate. Do NOT retry in a loop '
        'and do NOT absorb the work into the main loop. Wait for the window to clear, or ask '
        'the owner to explicitly authorize a burst (they set SPAWN_RATE_OVERRIDE=1 themselves).'
    )
}))" "$sr_recent" "$SPAWN_RATE_MAX" "$SPAWN_RATE_WINDOW" 2>/dev/null
            exit 0
        fi
        { echo "$sr_now" >> "$SPAWN_RATE_LOG"; } 2>/dev/null
    fi

    # ---- Policy 4: auto-burn-check — inject burn signal on the ALLOW path (2026-07-24) ----
    # Reached only when no deny policy above fired (a delegation is about to proceed).
    # Fail-open, always: any error in this block must fall through to a silent allow,
    # never a block and never corrupted output. Everything is wrapped + stderr-swallowed.
    #
    # (2026-09-03, Claude Code, per Kiro usage-guard-rewire design: the band is now
    # driven by the MAX of the two general windows read from the statusline JSON
    # cache, and the injected text names WHICH window is binding. fable_weekly is
    # excluded from banding: it is dispatch-scoped, not a burn signal. The old
    # bounded self-heal refresh, its background watchdog and its timeout var are
    # DELETED: a local file read cannot hang, so there is nothing to time-bound and
    # nothing to retry. -1 here now means exactly "the local usage cache is missing
    # or stale", with no second guess to make about it.)
    if [ "${USAGE_GUARD_BURNCHECK_OFF:-0}" != "1" ]; then
        {
            # ug_test_mode was resolved once above, with U_5H/U_7D already faked,
            # so band selection needs no separate test-mode plumbing here: it only
            # reuses the flag to prefix the injected text "[TEST-MODE]", so a fake
            # signal can never be mistaken for a real one.
            bc_test_mode="$ug_test_mode"
            bc_pct=$(usage_max "$U_5H" "$U_7D")

            # Name the binding dimension so the model knows WHICH window is tight.
            # On a tie the 5-hour window is named: it is the one that clears sooner.
            bc_dim="7-day"
            if [ "$U_5H" -ge 0 ] 2>/dev/null && [ "$U_5H" = "$bc_pct" ]; then
                bc_dim="5-hour"
            fi

            band=""
            if [ "$bc_pct" = "-1" ]; then
                band="unavailable"
            elif [ "$bc_pct" -ge 50 ] 2>/dev/null && [ "$bc_pct" -lt 70 ] 2>/dev/null; then
                band="shift-down"
            elif [ "$bc_pct" -ge 70 ] 2>/dev/null && [ "$bc_pct" -lt 90 ] 2>/dev/null; then
                band="forge-first"
            fi
            # bc_pct < 50 (the common case) → band stays empty → silent allow, no cost.

            if [ "$band" = "unavailable" ]; then
                bc_state_file="$BURNCHECK_DEGRADED_STATE_FILE"
                bc_cooldown="$BURNCHECK_DEGRADED_COOLDOWN"
            else
                bc_state_file="$BURNCHECK_STATE_FILE"
                bc_cooldown="$BURNCHECK_COOLDOWN"
            fi
            if [ "$bc_test_mode" = "1" ]; then
                bc_state_file="${bc_state_file}.testmode"
                bc_cooldown=0
            fi

            if [ -n "$band" ]; then
                now=$(date +%s)
                last=$(cat "$bc_state_file" 2>/dev/null)
                case "$last" in ''|*[!0-9]*) last=0 ;; esac
                elapsed=$(( now - last ))
                if [ "$elapsed" -ge "$bc_cooldown" ] 2>/dev/null; then
                    { echo "$now" > "$bc_state_file"; } 2>/dev/null
                    python3 -c "
import json, sys

pct       = sys.argv[1]
band      = sys.argv[2]
dim       = sys.argv[3]
test_mode = sys.argv[4] == '1'
prefix    = '[TEST-MODE] ' if test_mode else ''

if band == 'unavailable':
    ctx = (
        'Usage-guard burn signal UNAVAILABLE: the local usage cache '
        '(~/.claude/state/claude-usage.json) is missing, unreadable, or older than '
        'the staleness limit, so the guard has no rate-limit numbers for this '
        'dispatch. The guard is FAIL-OPEN: nothing is being blocked on usage right '
        'now, and that is NOT the same as having headroom. Do not assume headroom. '
        'Check before fanning out: run bash ~/.claude/hooks/usage-guard.sh pct, or '
        'read the percentages straight off the statusline.'
    )
    sysmsg = 'usage-guard: burn signal UNAVAILABLE (usage cache missing/stale): verify before fan-out'
elif band == 'shift-down':
    ctx = (
        f'Usage-guard burn signal: {dim} window at {pct}% of the Claude Code '
        'metered rate limit (SHIFT-DOWN band). Prefer haiku over sonnet where the '
        'task is mechanical, keep fan-out width small, and avoid opus unless the '
        'task is genuinely reasoning-heavy.'
    )
    sysmsg = f'usage-guard: {dim} window at {pct}%: SHIFT-DOWN band'
else:
    ctx = (
        f'Usage-guard burn signal: {dim} window at {pct}% of the Claude Code '
        'metered rate limit (FORGE-FIRST band). Route bounded, self-contained '
        'second-opinion work to the free Forge tier first; keep paid delegation to '
        'what genuinely needs repo/tool access or is time-critical; minimum viable '
        'fan-out width only.'
    )
    sysmsg = f'usage-guard: {dim} window at {pct}%: FORGE-FIRST band'

ctx = prefix + ctx
sysmsg = prefix + sysmsg

print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'additionalContext': ctx,
    },
    'systemMessage': sysmsg,
    'suppressOutput': True,
}))
" "$bc_pct" "$band" "$bc_dim" "$bc_test_mode" 2>/dev/null
                fi
            fi
        } || true
    fi
    ;;

  *)
    echo "usage-guard: unknown mode '$MODE'. Valid: pct | block | inform | refresh" >&2
    exit 1
    ;;
esac
