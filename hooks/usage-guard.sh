#!/usr/bin/env bash
# usage-guard.sh — Claude Code hook: usage-cap enforcement + conductor-model policy
# Four modes: pct | block | inform | refresh
#
# Conductor = role, not a fixed model. Policy 1 denies any subagent that is not
# sonnet/haiku/cheap-worker, regardless of which model is acting as conductor.
# This enforces the efficient-fable delegation design mechanically.
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
CHEAP_WORKERS="researcher|code-generator|tester"

# Cost cap for the active usage window, in USD — the proxy denominator.
# ccusage reports per-block cost but NOT the plan's true limit, so we approximate
# the window ceiling with a configurable cost budget. This is an ESTIMATE; the
# authoritative number is Claude Code's /usage command. Set USAGE_GUARD_COST_LIMIT
# to your own plan's window ceiling — the default below is only a placeholder.
COST_LIMIT="${USAGE_GUARD_COST_LIMIT:-100}"

# ---------- cache refresh (fail-open: a broken ccusage must not block work) ----------
refresh_cache() {
    local lockdir="${CACHE_FILE}.lock"
    # mkdir-based lock is POSIX-safe (works on macOS and Linux)
    mkdir "$lockdir" 2>/dev/null || return 0

    trap 'rmdir "$lockdir" 2>/dev/null' EXIT

    data=$(npx -y ccusage@latest blocks --json 2>/dev/null) || { rmdir "$lockdir" 2>/dev/null; return 0; }

    python3 - "$data" "$COST_LIMIT" <<'EOF'
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

    result=$?
    rmdir "$lockdir" 2>/dev/null
    return $result
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
    get_pct
    ;;

  refresh)
    refresh_cache > "$CACHE_FILE" &
    ;;

  inform)
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

        is_cheap=false
        case "$model" in
            sonnet|haiku) is_cheap=true ;;
        esac
        if echo "$subagent_type" | grep -qE "^($CHEAP_WORKERS)$"; then
            is_cheap=true
        fi

        if ! $is_cheap; then
            python3 -c "
import json
print(json.dumps({
    'decision': 'block',
    'reason': (
        'Conductor-model subagent denied. '
        'Agent calls must specify model: \"sonnet\" or \"haiku\", '
        'or use a pinned cheap worker via subagent_type (researcher / code-generator / tester). '
        'The conductor/manager model runs in the main loop only — never in subagents. '
        'Re-issue with an explicit cheap model or named worker.'
    )
}))"
            exit 0
        fi
    fi

    # ---- Policy 2: usage cap gate ----
    pct=$(get_pct)
    if [ "$pct" -ge "$BLOCK_PCT" ] 2>/dev/null; then
        python3 -c "
import json, sys
pct = int(sys.argv[1])
block = int(sys.argv[2])
print(json.dumps({
    'decision': 'block',
    'reason': (
        f'Usage cap gate: at {pct}% of cap proxy (block threshold: {block}%). '
        'Pause delegation and resume when usage drops. '
        'Run: bash ~/.claude/hooks/usage-guard.sh pct to check current level. '
        'Do NOT absorb delegation work into the main loop — wait and re-dispatch.'
    )
}))" "$pct" "$BLOCK_PCT"
        exit 0
    fi
    ;;

  *)
    echo "usage-guard: unknown mode '$MODE'. Valid: pct | block | inform | refresh" >&2
    exit 1
    ;;
esac
