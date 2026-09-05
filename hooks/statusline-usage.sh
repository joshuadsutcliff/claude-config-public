#!/usr/bin/env bash
set -uo pipefail

# statusline-usage.sh
# Renders a Claude Code status line, side-writes a Markdown usage summary
# when CLAUDE_USAGE_VAULT points at a valid directory (skipped otherwise),
# and writes a machine-readable JSON cache at $CLAUDE_USAGE_JSON_FILE that
# a separate PreToolUse hook (usage-guard.sh) reads.
#
# Never hard-fails (no `set -e`): a statusLine script must always print
# something, or the status line goes blank.

THROTTLE_SECONDS=30

# ---- resolve vault root from CLAUDE_USAGE_VAULT ----
# When unset (or not a directory), VAULT_ROOT stays empty and the Markdown
# side-write (Job A) below is simply skipped; the JSON cache (Job A3) and
# the status line (Job B) are unaffected.
VAULT_ROOT=""
if [ -n "${CLAUDE_USAGE_VAULT:-}" ] && [ -d "${CLAUDE_USAGE_VAULT:-}" ]; then
  VAULT_ROOT="${CLAUDE_USAGE_VAULT}"
fi

OUT_FILE=""
OUT_DIR=""
if [ -n "$VAULT_ROOT" ]; then
  OUT_FILE="${VAULT_ROOT}/_private/claude-usage.md"
  OUT_DIR="$(dirname "$OUT_FILE")"
fi

# ---- read stdin once ----
input="$(cat)"

# ---- detect parser ----
HAVE_JQ=0
HAVE_PY=0
if command -v jq >/dev/null 2>&1; then
  HAVE_JQ=1
elif command -v python3 >/dev/null 2>&1; then
  HAVE_PY=1
fi

# Extraction helpers. Each sets a global var. Empty string = absent/null/parse-failure.
get_jq() {
  # $1 = jq filter, uses `// empty` upstream in call sites for absence
  printf '%s' "$input" | jq -r "$1" 2>/dev/null
}

get_py() {
  # $1 = python dotted/bracket path expression evaluated against `d`
  python3 - "$1" <<'PYEOF' 2>/dev/null
import json, sys
expr = sys.argv[1]
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print("")
    sys.exit(0)
try:
    v = eval(expr, {"d": d})
except Exception:
    v = None
print("" if v is None else v)
PYEOF
}

extract() {
  # $1 = jq filter (with // empty), $2 = python expr against `d`
  if [ "$HAVE_JQ" = "1" ]; then
    printf '%s' "$input" | jq -r "$1" 2>/dev/null
  elif [ "$HAVE_PY" = "1" ]; then
    printf '%s' "$input" | get_py "$2"
  else
    echo ""
  fi
}

MODEL_NAME="$(extract '.model.display_name // empty' "d.get('model',{}).get('display_name')")"
DIR="$(extract '.workspace.current_dir // .cwd // empty' "d.get('workspace',{}).get('current_dir') or d.get('cwd')")"
CTX_PCT="$(extract '.context_window.used_percentage // empty' "d.get('context_window',{}).get('used_percentage')")"
FIVE_H="$(extract '.rate_limits.five_hour.used_percentage // empty' "d.get('rate_limits',{}).get('five_hour',{}).get('used_percentage')")"
FIVE_H_RESET="$(extract '.rate_limits.five_hour.resets_at // empty' "d.get('rate_limits',{}).get('five_hour',{}).get('resets_at')")"
SEVEN_D="$(extract '.rate_limits.seven_day.used_percentage // empty' "d.get('rate_limits',{}).get('seven_day',{}).get('used_percentage')")"
SEVEN_D_RESET="$(extract '.rate_limits.seven_day.resets_at // empty' "d.get('rate_limits',{}).get('seven_day',{}).get('resets_at')")"

# ---- read Fable weekly-usage cache (owned by a separate scraper) ----
# Cache is refreshed every ~30 min; 3600s = 2x that cadence before we call it stale.
FABLE_MAX_AGE=3600
FABLE_CACHE_FILE="${HOME}/.claude/state/fable-weekly.json"
FABLE_W=""
if [ -r "$FABLE_CACHE_FILE" ]; then
  fable_json="$(cat "$FABLE_CACHE_FILE" 2>/dev/null)"
  if [ -n "$fable_json" ]; then
    fable_val=""
    fable_captured=""
    if [ "$HAVE_JQ" = "1" ]; then
      fable_val="$(printf '%s' "$fable_json" | jq -r '.fable_weekly // empty' 2>/dev/null)"
      fable_captured="$(printf '%s' "$fable_json" | jq -r '.captured_at // empty' 2>/dev/null)"
    elif [ "$HAVE_PY" = "1" ]; then
      fable_val="$(printf '%s' "$fable_json" | python3 - <<'PYEOF' 2>/dev/null
import json, sys
try:
    d = json.loads(sys.stdin.read())
    v = d.get("fable_weekly")
    print("" if v is None else v)
except Exception:
    print("")
PYEOF
)"
      fable_captured="$(printf '%s' "$fable_json" | python3 - <<'PYEOF' 2>/dev/null
import json, sys
try:
    d = json.loads(sys.stdin.read())
    v = d.get("captured_at")
    print("" if v is None else v)
except Exception:
    print("")
PYEOF
)"
    fi

    case "$fable_val" in
      ''|*[!0-9.]*) fable_val="" ;;
    esac
    case "$fable_captured" in
      ''|*[!0-9]*) fable_captured="" ;;
    esac

    if [ -n "$fable_val" ] && [ -n "$fable_captured" ]; then
      fable_now_epoch="$(date +%s 2>/dev/null || echo 0)"
      fable_age=$(( fable_now_epoch - fable_captured ))
      if [ "$fable_age" -ge 0 ] && [ "$fable_age" -le "$FABLE_MAX_AGE" ]; then
        FABLE_W="$fable_val"
      fi
    fi
  fi
fi

DIR_NAME="${DIR##*/}"

# ---- helper: epoch -> human local time ----
human_time() {
  # $1 = epoch seconds; prints formatted local time or "" on failure
  local epoch="$1"
  [ -z "$epoch" ] && return 0
  # strip any trailing decimal
  epoch="${epoch%%.*}"
  date -r "$epoch" "+%Y-%m-%d %H:%M %Z" 2>/dev/null || date -d "@$epoch" "+%Y-%m-%d %H:%M %Z" 2>/dev/null || echo ""
}

# ---- Job A: side-write Markdown, throttled to 30s ----
should_write=1
if [ -z "$OUT_FILE" ]; then
  should_write=0
elif [ -f "$OUT_FILE" ]; then
  now_epoch="$(date +%s 2>/dev/null || echo 0)"
  mtime="$(stat -f %m "$OUT_FILE" 2>/dev/null || stat -c %Y "$OUT_FILE" 2>/dev/null || echo 0)"
  age=$(( now_epoch - mtime ))
  if [ "$age" -lt "$THROTTLE_SECONDS" ]; then
    should_write=0
  fi
fi

if [ "$should_write" = "1" ]; then
  mkdir -p "$OUT_DIR" 2>/dev/null

  today="$(date "+%Y-%m-%d" 2>/dev/null)"
  captured="$(date "+%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)"

  five_h_line="- **5-hour window:** absent from payload (no active subscriber session data yet)"
  if [ -n "$FIVE_H" ]; then
    five_h_reset_human="$(human_time "$FIVE_H_RESET")"
    [ -z "$five_h_reset_human" ] && five_h_reset_human="unknown"
    five_h_line="- **5-hour window:** $(printf '%.0f' "$FIVE_H")% used, resets ${five_h_reset_human}"
  fi

  seven_d_line="- **7-day window:** absent from payload (no active subscriber session data yet)"
  if [ -n "$SEVEN_D" ]; then
    seven_d_reset_human="$(human_time "$SEVEN_D_RESET")"
    [ -z "$seven_d_reset_human" ] && seven_d_reset_human="unknown"
    seven_d_line="- **7-day window:** $(printf '%.0f' "$SEVEN_D")% used, resets ${seven_d_reset_human}"
  fi

  fable_w_line=""
  if [ -n "$FABLE_W" ]; then
    fable_w_line="- **Fable weekly:** $(printf '%.0f' "$FABLE_W")% used"
  fi

  tmp_file="$(mktemp "${OUT_DIR}/.claude-usage.XXXXXX" 2>/dev/null)"
  if [ -n "$tmp_file" ]; then
    {
      echo "---"
      echo "type: note"
      echo "date: ${today}"
      echo "status: active"
      echo "tags: [vault-meta]"
      echo "---"
      echo ""
      echo "# Claude Code Subscription Usage"
      echo ""
      echo "${five_h_line}"
      echo "${seven_d_line}"
      [ -n "$fable_w_line" ] && echo "${fable_w_line}"
      echo ""
      echo "_captured: ${captured}_"
    } > "$tmp_file" 2>/dev/null

    mv -f "$tmp_file" "$OUT_FILE" 2>/dev/null
  fi
fi

# ---- Job A3: machine-readable JSON sink for usage-guard.sh (added 2026-09-03, Claude Code, per Kiro usage-guard-rewire design) ----
if [ "$should_write" = "1" ] && [ "${CLAUDE_USAGE_JSON_OFF:-}" != "1" ] && [ -n "$FIVE_H" ] && [ -n "$SEVEN_D" ]; then
  json_out_file="${CLAUDE_USAGE_JSON_FILE:-${HOME}/.claude/state/claude-usage.json}"
  json_out_dir="$(dirname "$json_out_file" 2>/dev/null)"

  if [ -n "$json_out_dir" ]; then
    mkdir -p "$json_out_dir" 2>/dev/null

    json_five_hour="$(printf '%.0f' "$FIVE_H" 2>/dev/null)"
    json_seven_day="$(printf '%.0f' "$SEVEN_D" 2>/dev/null)"

    json_context="null"
    if [ -n "$CTX_PCT" ]; then
      json_context_val="$(printf '%.0f' "$CTX_PCT" 2>/dev/null)"
      [ -n "$json_context_val" ] && json_context="$json_context_val"
    fi

    json_fable_weekly="null"
    if [ -n "$FABLE_W" ]; then
      json_fable_weekly_val="$(printf '%.0f' "$FABLE_W" 2>/dev/null)"
      [ -n "$json_fable_weekly_val" ] && json_fable_weekly="$json_fable_weekly_val"
    fi

    json_five_h_reset_int="${FIVE_H_RESET%%.*}"
    json_five_hour_resets_at="null"
    case "$json_five_h_reset_int" in
      ''|*[!0-9]*) ;;
      *) json_five_hour_resets_at="$json_five_h_reset_int" ;;
    esac

    json_seven_d_reset_int="${SEVEN_D_RESET%%.*}"
    json_seven_day_resets_at="null"
    case "$json_seven_d_reset_int" in
      ''|*[!0-9]*) ;;
      *) json_seven_day_resets_at="$json_seven_d_reset_int" ;;
    esac

    json_captured_at="$(date +%s 2>/dev/null)"
    [ -z "$json_captured_at" ] && json_captured_at="null"

    if [ -n "$json_five_hour" ] && [ -n "$json_seven_day" ]; then
      json_tmp_file="$(mktemp "${json_out_dir}/.claude-usage.XXXXXX" 2>/dev/null)"
      if [ -n "$json_tmp_file" ]; then
        {
          printf '{\n'
          printf '  "five_hour": %s,\n' "$json_five_hour"
          printf '  "five_hour_resets_at": %s,\n' "$json_five_hour_resets_at"
          printf '  "seven_day": %s,\n' "$json_seven_day"
          printf '  "seven_day_resets_at": %s,\n' "$json_seven_day_resets_at"
          printf '  "fable_weekly": %s,\n' "$json_fable_weekly"
          printf '  "context": %s,\n' "$json_context"
          printf '  "captured_at": %s\n' "$json_captured_at"
          printf '}\n'
        } > "$json_tmp_file" 2>/dev/null

        mv -f "$json_tmp_file" "$json_out_file" 2>/dev/null
      fi
    fi
  fi
fi

# ---- Job B: print the status line ----
line="[${MODEL_NAME:-Claude}]"
[ -n "$DIR_NAME" ] && line="${line} 📁 ${DIR_NAME}"
[ -n "$CTX_PCT" ] && line="${line} | ctx: $(printf '%.0f' "$CTX_PCT" 2>/dev/null || echo "$CTX_PCT")%"

limits=""
if [ -n "$FIVE_H" ]; then
  limits="5h: $(printf '%.0f' "$FIVE_H" 2>/dev/null || echo "$FIVE_H")%"
fi
if [ -n "$SEVEN_D" ]; then
  limits="${limits:+$limits }7d: $(printf '%.0f' "$SEVEN_D" 2>/dev/null || echo "$SEVEN_D")%"
fi
[ -n "$limits" ] && line="${line} | ${limits}"

echo "$line"
exit 0
