#!/usr/bin/env bash
# usage-guard.sh — Claude Code hook: usage-cap enforcement + conductor-model policy
# Four modes: pct | block | inform | refresh
#
# Conductor = role, not a fixed model. Policy 1 denies any subagent that does not
# EXPLICITLY specify sonnet/haiku (the enforced default for token-efficiency),
# an explicit opus (deliberate heavy delegation per CLAUDE.md rule 12), or a
# pinned cheap worker. Unspecified/inherited models are always denied.
# This enforces the efficient-fable delegation design mechanically.
# (2026-07-12: explicit opus allowed per the user; was previously denied.)
#
# auto-burn-check (2026-07-24): on the block-mode ALLOW path (no deny policy fired),
# inject the current burn signal + routing band into the model's context via
# PreToolUse additionalContext, cooldown-gated, so a fan-out never happens blind.
#
# Wired in ~/.claude/settings.json:
#   SessionStart   → refresh (async)
#   UserPromptSubmit → inform
#   PreToolUse Agent|Workflow → block

MODE="${1:-block}"
CACHE_FILE="${HOME}/.cache/claude-usage-guard.json"
CACHE_TTL="${USAGE_GUARD_CACHE_SECS:-180}"
BLOCK_PCT="${USAGE_GUARD_BLOCK_PCT:-90}"
WARN_PCT="${USAGE_GUARD_WARN_PCT:-70}"
CHEAP_WORKERS="researcher|code-generator|tester|code-reviewer"

# auto-burn-check: cooldown between context injections on the block ALLOW path,
# and the state file tracking the last injection time. USAGE_GUARD_BURNCHECK_OFF=1
# disables the whole feature (silent allow), same convention as other *_OFF vars.
BURNCHECK_COOLDOWN="${USAGE_GUARD_BURNCHECK_COOLDOWN:-120}"
BURNCHECK_STATE_FILE="${HOME}/.cache/claude-usage-guard-burncheck.ts"
# Genuine degradation (refresh attempted and still failed) is rare and persistent —
# a much longer, separate cooldown avoids repeating the same noisy alarm every
# normal-band interval. (2026-07-24, field-report fix: routine TTL expiry was being
# misreported as degradation because burncheck never attempted a refresh itself.)
BURNCHECK_DEGRADED_COOLDOWN="${USAGE_GUARD_BURNCHECK_DEGRADED_COOLDOWN:-900}"
BURNCHECK_DEGRADED_STATE_FILE="${HOME}/.cache/claude-usage-guard-burncheck-degraded.ts"
# Hard bound on the synchronous self-heal refresh attempted before declaring the
# burn signal unavailable — this runs inside a PreToolUse hook and must never stall
# a delegation on a hung/broken ccusage.
BURNCHECK_REFRESH_TIMEOUT="${USAGE_GUARD_BURNCHECK_REFRESH_TIMEOUT:-5}"

# Cost cap for the active 5-hour window, in USD — the proxy denominator.
# ccusage reports per-block cost but NOT the plan's true limit, so we approximate
# the 5h ceiling with a configurable cost budget. Calibrated 2026-06-18 against
# /usage: an active block at $5.17 read as ~2% used → 5h cap ≈ $250.
# This is an ESTIMATE; the authoritative number is Claude Code's /usage command.
# Tune via USAGE_GUARD_COST_LIMIT if /usage and the proxy drift apart.
COST_LIMIT="${USAGE_GUARD_COST_LIMIT:-250}"

# M1 spawn-rate limiter (2026-07-26, Kiro battery postmortem — mechanical control).
# Hard-denies Agent/Workflow spawns beyond SPAWN_RATE_MAX within a rolling
# SPAWN_RATE_WINDOW. The log is MACHINE-GLOBAL (not per-session): burst
# parallelism across concurrent sessions is exactly the failure mode the pct
# proxy cannot see. Override for an explicitly user-authorized burst:
# SPAWN_RATE_OVERRIDE=1 (per-session env var, never set by the model).
SPAWN_RATE_MAX="${USAGE_GUARD_SPAWN_RATE_MAX:-4}"
SPAWN_RATE_WINDOW="${USAGE_GUARD_SPAWN_RATE_WINDOW:-300}"
SPAWN_RATE_LOG="${HOME}/.cache/claude-spawn-rate.log"

# ccusage version spec. Pinned to a MAJOR (not @latest) so a breaking change to
# the `blocks --json` schema can't silently land and make the parser fail-open
# (which would disable the cap guard without warning). Bump deliberately after
# verifying the schema. Override with USAGE_GUARD_CCUSAGE_SPEC.
CCUSAGE_SPEC="${USAGE_GUARD_CCUSAGE_SPEC:-ccusage@20}"
# Marker written when ccusage fails to run, so `inform` can surface the degraded
# (fail-open) state instead of the guard silently going blind.
DEGRADED_FILE="${CACHE_FILE}.degraded"

# ---------- cache refresh (fail-open: a broken ccusage must not block work) ----------
# Writes to a temp file and atomically moves into place ONLY on valid output.
# Never truncates the existing cache: an in-flight lock, a ccusage failure, or a
# no-active-block result must leave the last good cache intact (a redirect-at-callsite
# truncation here was the old "-1 despite fresh cache" bug).
refresh_cache() {
    local lockdir="${CACHE_FILE}.lock"
    # mkdir-based lock is POSIX-safe (works on macOS and Linux)
    mkdir "$lockdir" 2>/dev/null || return 0

    trap 'rmdir "$lockdir" 2>/dev/null' EXIT

    data=$(npx -y "$CCUSAGE_SPEC" blocks --json 2>/dev/null) || {
        : > "$DEGRADED_FILE" 2>/dev/null   # tracking degraded — surfaced by `inform`
        rmdir "$lockdir" 2>/dev/null; return 0;
    }
    rm -f "$DEGRADED_FILE" 2>/dev/null      # ccusage ran → clear any prior degraded mark

    local tmp="${CACHE_FILE}.tmp.$$"
    python3 - "$data" "$COST_LIMIT" > "$tmp" <<'EOF'
import sys, json, time

data_str   = sys.argv[1]
try:
    cost_limit = float(sys.argv[2])
except Exception:
    cost_limit = 0.0

try:
    data = json.loads(data_str)
except Exception:
    sys.exit(0)

blocks = data if isinstance(data, list) else data.get('blocks', [])
if not blocks:
    sys.exit(0)

active = next((b for b in blocks if b.get('isActive')), None)
if not active:
    sys.exit(0)

# Proxy = consumed cost of the active 5h block as a share of the configured cap.
# (Cost, not raw totalTokens: ccusage sums cache-read tokens at full weight, which
#  badly overstates usage vs. /usage's cost/usage-weighted metric.) Denominator is
# an absolute budget — NOT the max across historical blocks, which made any
# record-setting active block read as ~100% regardless of the real limit.
cur_cost = active.get('costUSD') or 0.0
pct = int(round(cur_cost * 100 / cost_limit)) if cost_limit > 0 else -1

print(json.dumps({
    "pct": pct,
    "cost": round(cur_cost, 2),
    "cost_limit": cost_limit,
    "ts": int(time.time()),
}))
EOF

    if [ -s "$tmp" ]; then
        mv -f "$tmp" "$CACHE_FILE"
    else
        rm -f "$tmp"
    fi
    rmdir "$lockdir" 2>/dev/null
    return 0
}

# ---------- read pct from cache (fail-open → -1 if stale/missing) ----------
get_pct() {
    if [ ! -f "$CACHE_FILE" ]; then
        echo "-1"
        return
    fi
    python3 - "$CACHE_FILE" "$CACHE_TTL" <<'EOF'
import sys, json, time

cache_path = sys.argv[1]
ttl        = int(sys.argv[2])

try:
    with open(cache_path) as f:
        d = json.load(f)
    age = int(time.time()) - d.get('ts', 0)
    if age < ttl:
        print(d.get('pct', -1))
    else:
        print(-1)
except Exception:
    print(-1)
EOF
}

# ---------- modes ----------
case "$MODE" in

  pct)
    # Manual/stay-within-limits check: self-heal a stale or missing cache with a
    # synchronous refresh (hooks use `block`/`inform`, which stay fast + fail-open).
    pct=$(get_pct)
    if [ "$pct" = "-1" ]; then
        refresh_cache
        pct=$(get_pct)
    fi
    echo "$pct"
    ;;

  refresh)
    refresh_cache &
    ;;

  refresh_sync)
    # Internal mode, not part of the documented interface: a BLOCKING refresh_cache
    # call, invoked recursively (via `bash "$0" refresh_sync`, wrapped in `timeout`
    # by burncheck) so it can be hard-time-bounded from the outside without
    # duplicating pct mode's self-heal logic.
    refresh_cache
    ;;

  inform)
    if [ -f "$DEGRADED_FILE" ]; then
        cat <<EOF
[usage-guard] NOTICE: usage tracking is DEGRADED — \`$CCUSAGE_SPEC\` failed to run, so the cap guard is fail-open (the 90% hard-block will NOT fire). Check npx/ccusage availability; this clears automatically on the next successful refresh.
EOF
    fi
    pct=$(get_pct)
    if [ "$pct" -ge "$WARN_PCT" ] 2>/dev/null; then
        cat <<EOF
[usage-guard] WARNING: ~${pct}% of the estimated 5-hour cost cap (\$${COST_LIMIT}; warn at ${WARN_PCT}%).
This is an approximation — confirm with Claude Code's /usage before throttling. If they disagree, tune USAGE_GUARD_COST_LIMIT. Prefer small waves near the cap.
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
        'or use a pinned cheap worker via subagent_type (researcher / code-generator / tester / code-reviewer). '
        'Unspecified models inherit the conductor and are always denied — '
        'the conductor/manager model runs in the main loop only. '
        'Re-issue with an explicit model or named worker.'
    )
}))"
            exit 0
        fi
    fi

    # ---- Policy 2: usage cap gate ----
    # Test-mode override (C7 prerequisite): when both USAGE_GUARD_TEST_MODE=1 and
    # USAGE_GUARD_FAKE_PCT=<n> are set, the gate evaluates the fake pct instead of
    # the real cache value. Either var unset → byte-identical to prior behavior.
    p2_test_mode=0
    if [ "${USAGE_GUARD_TEST_MODE:-0}" = "1" ] && [ -n "${USAGE_GUARD_FAKE_PCT:-}" ]; then
        p2_test_mode=1
        pct="$USAGE_GUARD_FAKE_PCT"
    else
        pct=$(get_pct)
    fi
    if [ "$pct" -ge "$BLOCK_PCT" ] 2>/dev/null; then
        python3 -c "
import json, sys
pct = int(sys.argv[1])
block = int(sys.argv[2])
test_mode = sys.argv[3] == '1'
prefix = '[TEST-MODE] ' if test_mode else ''
print(json.dumps({
    'decision': 'block',
    'reason': (
        prefix +
        f'Usage cap gate: at {pct}% of cap proxy (block threshold: {block}%). '
        'Pause delegation and resume when usage drops. '
        'Run: bash ~/.claude/hooks/usage-guard.sh pct to check current level. '
        'Do NOT absorb delegation work into the main loop — wait and re-dispatch.'
    )
}))" "$pct" "$BLOCK_PCT" "$p2_test_mode"
        exit 0
    fi

    # ---- Policy 3: gh-auth mutex — gh active account is machine-global; prose rule
    # failed 2026-07-20, hook-enforced per Kiro adjudication 2026-07-21 ----
    # Narrow check: only Agent/Workflow spawns whose prompt touches gh credential
    # state. Any parse failure here falls through to ALLOW (fail-open) — this must
    # never be the reason a legitimate spawn is blocked.
    if [ "$tool_name" = "Agent" ] || [ "$tool_name" = "Workflow" ]; then
        prompt_text=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    print(d.get('tool_input', {}).get('prompt', '') or '')
except Exception:
    print('')
" "$input" 2>/dev/null)

        if [ -n "$prompt_text" ] && echo "$prompt_text" | grep -qE 'gh auth (switch|login)' 2>/dev/null; then
            LOCK_DIR="${HOME}/.claude/locks"
            LOCK_FILE="${LOCK_DIR}/gh-auth.lock"
            mkdir -p "$LOCK_DIR" 2>/dev/null

            # Atomic acquire via mkdir (same pattern as refresh_cache): a bare
            # mtime-check-then-touch is TOCTOU — two same-message spawns both read
            # "no lock" and both pass (Opus review 2026-07-21). mkdir admits exactly
            # one; losers must prove the lock stale to pass. The lock is a DIRECTORY
            # now; a legacy file lock from the old code is aged out the same way.
            lock_stat_age() {
                python3 -c "
import os, time, sys
try:
    print(int(time.time() - os.path.getmtime(sys.argv[1])))
except Exception:
    print(9999999)
" "$LOCK_FILE" 2>/dev/null
            }
            deny_gh_mutex() {
                python3 -c "
import json
print(json.dumps({
    'decision': 'block',
    'reason': (
        'gh-auth mutex: another gh-credential-touching agent spawned <10 min ago. '
        \"gh's active account is machine-global — serialize. If the prior worker has \"
        'finished, remove ~/.claude/locks/gh-auth.lock and retry.'
    )
}))" 2>/dev/null
                exit 0
            }

            if ! mkdir "$LOCK_FILE" 2>/dev/null; then
                lock_age=$(lock_stat_age)
                case "$lock_age" in ''|*[!0-9]*) lock_age=9999999 ;; esac
                if [ "$lock_age" -lt 600 ] 2>/dev/null; then
                    deny_gh_mutex
                fi
                # Stale (or unstattable) — clear and re-acquire. If another spawn
                # wins the re-acquire, its lock reads fresh → block; if the lock
                # still can't be created/statted (broken dir), fail OPEN → allow.
                rm -rf "$LOCK_FILE" 2>/dev/null
                if ! mkdir "$LOCK_FILE" 2>/dev/null; then
                    lock_age=$(lock_stat_age)
                    case "$lock_age" in ''|*[!0-9]*) lock_age=9999999 ;; esac
                    if [ "$lock_age" -lt 600 ] 2>/dev/null; then
                        deny_gh_mutex
                    fi
                fi
            fi
        fi
    fi

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
        'the user to explicitly authorize a burst (they set SPAWN_RATE_OVERRIDE=1 themselves).'
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
    if [ "${USAGE_GUARD_BURNCHECK_OFF:-0}" != "1" ]; then
        {
            # Test-mode override (C7 prerequisite, 2026-07-25): when BOTH vars are
            # set, band selection uses the fake pct instead of the real one, and
            # the injected text is prefixed "[TEST-MODE]" so it can never be
            # mistaken for a real signal. Either var unset → byte-identical to
            # prior behavior (bc_test_mode stays 0, nothing below changes).
            bc_test_mode=0
            if [ "${USAGE_GUARD_TEST_MODE:-0}" = "1" ] && [ -n "${USAGE_GUARD_FAKE_PCT:-}" ]; then
                bc_test_mode=1
            fi

            bc_pct="$pct"
            if [ "$bc_test_mode" = "1" ]; then
                bc_pct="$USAGE_GUARD_FAKE_PCT"
            elif [ "$bc_pct" = "-1" ]; then
                # -1 just means "cache missing/stale per TTL" — that's routine (any
                # session running >CACHE_TTL with no refresh hits this every time),
                # NOT genuine degradation. Attempt one bounded synchronous self-heal
                # (the same refresh_cache `pct` mode already calls) before concluding
                # the signal is truly unavailable. Hard-timeout so a hung/broken
                # ccusage can never stall this PreToolUse hook. If refresh_cache's
                # own mkdir-lock is already held (e.g. a SessionStart async refresh
                # in flight), it returns immediately (fail-fast, not a stall) —
                # timeout is a backstop for a genuinely hung ccusage/npx, not the
                # expected path.
                # Portable bound (no GNU `timeout` on stock macOS — same gotcha
                # documented for the gh-auth mutex tests): background the refresh,
                # run a watchdog that kills it after BURNCHECK_REFRESH_TIMEOUT, wait
                # for whichever finishes first, then reap the watchdog.
                bash "$0" refresh_sync >/dev/null 2>/dev/null &
                bc_refresh_pid=$!
                ( sleep "$BURNCHECK_REFRESH_TIMEOUT"; kill "$bc_refresh_pid" 2>/dev/null ) &
                bc_watchdog_pid=$!
                wait "$bc_refresh_pid" 2>/dev/null
                kill "$bc_watchdog_pid" 2>/dev/null
                wait "$bc_watchdog_pid" 2>/dev/null
                bc_pct=$(get_pct)
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

pct        = sys.argv[1]
band       = sys.argv[2]
cost_limit = sys.argv[3]
test_mode  = sys.argv[4] == '1'
prefix     = '[TEST-MODE] ' if test_mode else ''

if band == 'unavailable':
    ctx = (
        'Usage-guard burn signal UNAVAILABLE — a bounded self-heal refresh was just '
        'attempted and still failed (ccusage broken, network down, or a refresh lock '
        'held too long), so this is genuine degradation, not routine cache expiry. '
        'Flying blind on the 5-hour cap proxy. Before fanning out multi-agent work, '
        'run: bash ~/.claude/hooks/usage-guard.sh pct to check manually and inspect '
        'why ccusage is failing. Do not assume headroom.'
    )
    sysmsg = 'usage-guard: burn signal genuinely UNAVAILABLE — verify manually before fan-out'
elif band == 'shift-down':
    ctx = (
        f'Usage-guard burn signal: ~{pct}% of the \${cost_limit} 5h cap proxy (SHIFT-DOWN band). '
        'Prefer haiku over sonnet where the task is mechanical, keep fan-out width small, '
        'avoid opus unless the task is genuinely reasoning-heavy.'
    )
    sysmsg = f'usage-guard: {pct}% of 5h cap proxy — SHIFT-DOWN band'
else:
    ctx = (
        f'Usage-guard burn signal: ~{pct}% of the \${cost_limit} 5h cap proxy (FORGE-FIRST band). '
        'Route bounded, self-contained second-opinion work to the free Forge tier first; '
        'keep paid delegation to what genuinely needs repo/tool access or is time-critical; '
        'minimum viable fan-out width only.'
    )
    sysmsg = f'usage-guard: {pct}% of 5h cap proxy — FORGE-FIRST band'

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
" "$bc_pct" "$band" "$COST_LIMIT" "$bc_test_mode" 2>/dev/null
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
