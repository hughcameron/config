#!/usr/bin/env bash
# Claude Usage Analytics — CLI tool
# Analyzes Claude Code usage data and displays cost/usage & pacing charts.
#
# Engines: duckdb (aggregation), ccusage (pacing, current pricing), uplot/youplot
# (charts), jq. No nushell dependency — the SQL models in ./models/ are unchanged.
set -uo pipefail

# --- Configuration ---
CLAUDE_USAGE_DIR="${HOME}/.config/nushell/analysis/claude-usage"
DATA_DIR="${CLAUDE_USAGE_DIR}/data"
MODELS_DIR="${CLAUDE_USAGE_DIR}/models"
DB_PATH="${DATA_DIR}/usage.db"
PRICING_CACHE="${DATA_DIR}/pricing.json"
PRICING_CSV="${DATA_DIR}/pricing.csv"
PRICING_URL="https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
PRICING_CACHE_HOURS=24
LIMITS_LOG="${DATA_DIR}/limits-log.jsonl"

# --- Small utilities ---
reverse_lines() { awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}'; }

# Value of `--flag V` or `--flag=V` from an argument list; empty if absent.
get_flag_val() {
  local flag="$1"; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      "$flag") printf '%s' "${2:-}"; return;;
      "$flag"=*) printf '%s' "${1#*=}"; return;;
    esac
    shift
  done
}
has_flag() {
  local flag="$1"; shift
  local a; for a in "$@"; do [ "$a" = "$flag" ] && return 0; done
  return 1
}

# --- Date helpers (BSD/macOS first, GNU fallback) ---
d_month_start_since() { date +%Y%m01; }
d_days_in_month()     { date -v1d -v+1m -v-1d +%d 2>/dev/null || date -d "$(date +%Y-%m-01) +1 month -1 day" +%d; }
d_prev_month_first()  { date -v1d -v-1m +%Y%m01 2>/dev/null || date -d "$(date +%Y-%m-01) -1 month" +%Y%m01; }
d_prev_month_last()   { date -v1d -v-1d +%Y%m%d 2>/dev/null || date -d "$(date +%Y-%m-01) -1 day" +%Y%m%d; }
d_days_ago()          { date -v-"$1"d +%Y%m%d 2>/dev/null || date -d "$1 days ago" +%Y%m%d; }
d_month_year()        { date +'%B %Y'; }

iso_to_epoch() {  # ISO8601 (…Z) -> epoch seconds
  local ts="$1" e
  e=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null) && { printf '%s' "$e"; return; }
  e=$(date -u -d "$ts" +%s 2>/dev/null) && { printf '%s' "$e"; return; }
  return 1
}
epoch_to_disp() { date -r "$1" +'%a %d %b %H:%M' 2>/dev/null || date -d "@$1" +'%a %d %b %H:%M'; }

# --- Pricing (dynamic, from the LiteLLM feed) ---
pricing_cache_valid() {
  [ -f "$PRICING_CACHE" ] || return 1
  local mtime now age
  mtime=$(stat -f %m "$PRICING_CACHE" 2>/dev/null || stat -c %Y "$PRICING_CACHE" 2>/dev/null) || return 1
  now=$(date +%s)
  age=$(( (now - mtime) / 3600 ))
  [ "$age" -lt "$PRICING_CACHE_HOURS" ]
}

fetch_pricing() {
  local force=0
  [ "${1:-}" = "--force" ] && force=1
  if [ $force -eq 0 ] && pricing_cache_valid; then return 0; fi

  echo "Fetching pricing data..."
  mkdir -p "$DATA_DIR"
  curl -fsSL "$PRICING_URL" -o "$PRICING_CACHE"

  # Dynamically select every first-party Anthropic Claude model from the feed
  # (litellm_provider == "anthropic"), keyed on the bare model id — exactly what
  # Claude Code writes to its transcripts. Auto-covers new models; no hardcoded
  # allowlist that would silently price anything newer at $0.
  echo "Processing pricing data..."
  {
    echo "model_name,input_cost_per_token,output_cost_per_token,cache_creation_cost_per_token,cache_read_cost_per_token"
    jq -r '
      to_entries[]
      | select((.value | type == "object")
               and (.value.litellm_provider == "anthropic")
               and (.key | startswith("claude")))
      | [ .key,
          (.value.input_cost_per_token // 0),
          (.value.output_cost_per_token // 0),
          (.value.cache_creation_input_token_cost // 0),
          (.value.cache_read_input_token_cost // 0) ]
      | @csv
    ' "$PRICING_CACHE"
  } > "$PRICING_CSV"

  local n; n=$(( $(wc -l < "$PRICING_CSV") - 1 ))
  echo "Pricing data cached (${n} Claude models)."
}

# --- DuckDB pipeline ---
# DuckDB list literal of JSONL globs, for roots that actually contain transcripts.
# DuckDB expands the `**` itself, so we only use `find` to decide which roots to
# include (keeps this working on the system bash 3.2, which lacks globstar).
build_jsonl_list() {
  local roots=() r matched=()
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    local IFS=','
    for r in $CLAUDE_CONFIG_DIR; do roots+=("${r/#\~/$HOME}/projects"); done
  else
    roots+=("${HOME}/.config/claude/projects")
    roots+=("${HOME}/.claude/projects")
  fi
  for r in "${roots[@]}"; do
    [ -d "$r" ] || continue
    if find "$r" -name '*.jsonl' -print -quit 2>/dev/null | read -r _; then
      matched+=("${r}/**/*.jsonl")
    fi
  done
  if [ ${#matched[@]} -eq 0 ]; then
    echo "No JSONL files found in any configured path" >&2
    return 1
  fi
  local out="[" first=1 g
  for g in "${matched[@]}"; do
    [ $first -eq 1 ] && first=0 || out+=","
    out+="'${g}'"
  done
  out+="]"
  printf '%s' "$out"
}

# Run a SQL model file, substituting $token=value pairs, silently (DDL).
run_sql() {
  local file="$1"; shift
  local sql; sql="$(cat "${MODELS_DIR}/${file}")"
  local pair
  for pair in "$@"; do
    sql="${sql//${pair%%=*}/${pair#*=}}"
  done
  printf '%s' "$sql" | duckdb -init /dev/null "$DB_PATH" >/dev/null
}

query_db() { printf '%s' "$1" | duckdb -init /dev/null -csv "$DB_PATH"; }

build_db() {
  mkdir -p "$DATA_DIR"
  rm -f "$DB_PATH"
  fetch_pricing
  local jsonl_list; jsonl_list="$(build_jsonl_list)" || return 1

  run_sql 01_load_data.sql "\$jsonl_glob=${jsonl_list}"
  run_sql 02_staging.sql
  run_sql 03_pricing.sql "\$pricing_csv_path='${PRICING_CSV}'"
  run_sql 04_usage_facts.sql
  run_sql 05_aggregates.sql
  run_sql 06_sessions.sql
  run_sql 07_billing_blocks.sql

  # Surface any models present in the data but missing from pricing — they are
  # counted at $0. '<synthetic>' rows are expected placeholders and excluded.
  local unpriced
  unpriced="$(query_db "SELECT DISTINCT model_name FROM stg_usage WHERE model_name NOT IN (SELECT model_name FROM dim_pricing) AND model_name NOT LIKE '<%>' ORDER BY model_name" | tail -n +2)"
  if [ -n "$unpriced" ]; then
    local count; count=$(printf '%s\n' "$unpriced" | grep -c .)
    echo "⚠  ${count} model(s) in your data have no pricing (counted at \$0):"
    printf '%s\n' "$unpriced" | sed 's/^/     - /'
    echo "   Re-run 'ccu refresh-pricing' once LiteLLM lists them, or check the model id."
  fi
}

# --- ccusage (pacing data source) ---
ccusage_raw() {
  if command -v bunx >/dev/null 2>&1; then
    bunx ccusage@latest "$@" 2>/dev/null
  elif command -v npx >/dev/null 2>&1; then
    npx --yes ccusage@latest "$@" 2>/dev/null
  else
    echo "ccusage needs 'bunx' or 'npx' on PATH — install bun (brew install bun) or node" >&2
    return 1
  fi
}
ccusage_daily_json() {  # $1 = since YYYYMMDD -> [{period,totalCost,totalTokens}] sorted
  ccusage_raw daily --json --since "$1" | jq '[.daily[] | {period, totalCost, totalTokens}] | sort_by(.period)'
}
last_month_total() {  # $1 = tokens flag (0/1)
  local metric; [ "$1" = "1" ] && metric=totalTokens || metric=totalCost
  ccusage_raw daily --json --since "$(d_prev_month_first)" --until "$(d_prev_month_last)" \
    | jq --arg m "$metric" '[.daily[]? | .[$m]] | add // 0'
}
prior_7day_total() {
  ccusage_raw daily --json --since "$(d_days_ago 14)" --until "$(d_days_ago 7)" \
    | jq '[.daily[]? | .totalCost] | add // 0'
}

# --- Chart commands (DuckDB bars) ---
cmd_daily() {
  local days; days="$(get_flag_val --days "$@")"; days="${days:-30}"
  build_db
  query_db "SELECT strftime('%Y-%m-%d', event_date) AS date, ROUND(cost_usd, 4) AS cost FROM agg_daily ORDER BY event_date DESC LIMIT ${days}" \
    | tail -n +2 | reverse_lines \
    | uplot bar -d ',' -t "Daily Cost (Last ${days} Days)" --ylabel "USD"
}
cmd_weekly() {
  local weeks; weeks="$(get_flag_val --weeks "$@")"; weeks="${weeks:-12}"
  build_db
  query_db "SELECT strftime('%Y-%m-%d', event_week) AS week, ROUND(cost_usd, 4) AS cost FROM agg_weekly ORDER BY event_week DESC LIMIT ${weeks}" \
    | tail -n +2 | reverse_lines \
    | uplot bar -d ',' -t "Weekly Cost (Last ${weeks} Weeks)" --ylabel "USD"
}
cmd_monthly() {
  local months; months="$(get_flag_val --months "$@")"; months="${months:-6}"
  build_db
  query_db "SELECT strftime('%Y-%m', event_month) AS month, ROUND(cost_usd, 4) AS cost FROM agg_monthly ORDER BY event_month DESC LIMIT ${months}" \
    | tail -n +2 | reverse_lines \
    | uplot bar -d ',' -t "Monthly Cost (Last ${months} Months)" --ylabel "USD"
}
cmd_sessions() {
  local limit; limit="$(get_flag_val --limit "$@")"; limit="${limit:-20}"
  build_db
  query_db "SELECT LEFT(session_id::VARCHAR, 8) AS session, ROUND(cost_usd, 4) AS cost FROM agg_sessions ORDER BY cost_usd DESC LIMIT ${limit}" \
    | tail -n +2 | reverse_lines \
    | uplot barplot -d ',' -t "Top ${limit} Sessions by Cost" --ylabel "USD"
}
cmd_blocks() {
  local limit; limit="$(get_flag_val --limit "$@")"; limit="${limit:-20}"
  build_db
  query_db "SELECT block_id AS block, ROUND(cost_usd, 4) AS cost FROM agg_billing_blocks ORDER BY block_start DESC LIMIT ${limit}" \
    | tail -n +2 | reverse_lines \
    | uplot bar -d ',' -t "Recent 5-Hour Billing Blocks" --ylabel "USD"
}
cmd_status() {
  build_db
  local row
  row="$(query_db "SELECT block_id, strftime('%Y-%m-%d %H:%M', block_start) AS started, message_count, ROUND(cost_usd, 4) AS cost_usd, is_active, ROUND(hours_remaining, 2) AS hours_left FROM agg_billing_blocks ORDER BY block_start DESC LIMIT 1" | tail -n +2)"
  if [ -z "$row" ]; then echo "No usage data found."; return; fi
  local block_id started message_count cost_usd is_active hours_left
  IFS=',' read -r block_id started message_count cost_usd is_active hours_left <<<"$row"
  echo "Current Block: ${block_id}"
  echo "Started: ${started}"
  echo "Messages: ${message_count}"
  echo "Cost: \$${cost_usd}"
  if [ "$is_active" = "true" ]; then
    echo "Status: ACTIVE (${hours_left} hours remaining)"
  else
    echo "Status: EXPIRED"
  fi
}
cmd_refresh_pricing() { fetch_pricing --force; echo "Pricing data refreshed."; }

# --- Pacing / burndown charts (ccusage + youplot) ---
cmd_pace_month() {
  local budget tokens=0
  budget="$(get_flag_val --budget "$@")"
  has_flag --tokens "$@" && tokens=1

  local since rows len
  since="$(d_month_start_since)"
  rows="$(ccusage_daily_json "$since")" || return 1
  len="$(jq 'length' <<<"$rows")"
  [ "$len" -eq 0 ] && { echo "No usage recorded yet this month."; return; }

  local metric ylabel unit
  if [ $tokens -eq 1 ]; then metric=totalTokens; ylabel=tokens; unit=''
  else metric=totalCost; ylabel=USD; unit='$'; fi

  local dim tsv elapsed so_far
  dim="$(d_days_in_month)"
  tsv="$(jq -r --arg m "$metric" '.[] | [(.period[8:10] | tonumber), .[$m]] | @tsv' <<<"$rows")"
  read -r elapsed so_far <<<"$(awk -F'\t' '{c+=$2; d=$1} END{print d, c}' <<<"$tsv")"

  local reference lm
  if [ -n "$budget" ]; then
    reference="$budget"
  else
    lm="$(last_month_total "$tokens")"
    if awk "BEGIN{exit !(${lm}>0)}"; then reference="$lm"
    else reference="$(awk -v s="$so_far" -v e="$elapsed" -v d="$dim" 'BEGIN{print s/e*d}')"; fi
  fi

  { echo "day,actual,pace"
    awk -F'\t' -v dim="$dim" -v ref="$reference" '{c+=$2; printf "%d,%.2f,%.2f\n", $1, c, ref/dim*$1}' <<<"$tsv"
  } | uplot lines -d ',' -H --fmt xyy -t "Monthly pacing — $(d_month_year)" --xlabel "day of month" --ylabel "$ylabel"

  local projected status
  projected="$(awk -v s="$so_far" -v e="$elapsed" -v d="$dim" 'BEGIN{print s/e*d}')"
  status="$(awk -v p="$projected" -v r="$reference" 'BEGIN{print (p>r)?"OVER":"under"}')"
  printf '  so far %s%.2f  ·  reference %s%.2f  ·  projected month-end %s%.2f [%s]\n' \
    "$unit" "$so_far" "$unit" "$reference" "$unit" "$projected" "$status"
}

pace_week_proxy() {  # $1 = ceiling (optional)
  local ceiling="${1:-}"
  local rows len tsv total reference p
  rows="$(ccusage_daily_json "$(d_days_ago 7)")" || return 1
  len="$(jq 'length' <<<"$rows")"
  [ "$len" -eq 0 ] && { echo "No usage in the last 7 days."; return; }
  tsv="$(jq -r '.[] | [.totalCost] | @tsv' <<<"$rows")"
  total="$(awk '{c+=$1} END{print c}' <<<"$tsv")"
  if [ -n "$ceiling" ]; then
    reference="$ceiling"
  else
    p="$(prior_7day_total)"
    if awk "BEGIN{exit !(${p}>0)}"; then reference="$p"; else reference="$total"; fi
  fi
  { echo "day,actual,pace"
    awk -v ref="$reference" '{c+=$1; printf "%d,%.2f,%.2f\n", NR, c, ref/7*NR}' <<<"$tsv"
  } | uplot lines -d ',' -H --fmt xyy -t "Weekly pacing — ccusage cost proxy" --xlabel "day of 7-day window" --ylabel "USD"
  printf '  last 7 days $%.2f  ·  reference ceiling $%.2f\n' "$total" "$reference"
}

cmd_pace_week() {
  if has_flag --proxy "$@"; then pace_week_proxy "$(get_flag_val --ceiling "$@")"; return; fi

  local wk n
  if [ -f "$LIMITS_LOG" ]; then
    wk="$(jq -c 'select(.seven_day != null)' "$LIMITS_LOG" 2>/dev/null | jq -s 'sort_by(.ts)')"
  else
    wk="[]"
  fi
  n="$(jq 'length' <<<"$wk")"
  if [ "$n" -lt 2 ]; then
    echo "Weekly-limit history is still building — ${n} sample(s) logged so far."
    echo "The statusline records the real 7-day usage % as you work with Claude Code."
    echo "For a view you can use right now:  ccu pace week --proxy"
    return
  fi

  # Isolate the current weekly cycle. Claude Code's resets_at is a Unix epoch;
  # all samples in a cycle share it. Fall back to a drop-detection cut if absent.
  local latest_reset cycle
  latest_reset="$(jq -r '.[-1].resets_at // ""' <<<"$wk")"
  if [ -n "$latest_reset" ] && [ "$latest_reset" != "null" ]; then
    cycle="$(jq -c --argjson r "$latest_reset" '[.[] | select(.resets_at == $r)]' <<<"$wk")"
  else
    cycle="$(jq -c 'def cut: . as $a | (reduce range(1; length) as $i (0; if ($a[$i].seven_day < ($a[$i-1].seven_day - 20)) then $i else . end)) as $s | $a[$s:]; cut' <<<"$wk")"
  fi

  # Weekly window (168h) ending at reset. resets_at is an epoch int; keep ISO and
  # last-sample fallbacks for robustness.
  local last_ts last_ts_ep reset_ep window_start
  last_ts="$(jq -r '.[-1].ts' <<<"$cycle")"
  last_ts_ep="$(iso_to_epoch "$last_ts")"
  if printf '%s' "$latest_reset" | grep -qE '^[0-9]+$'; then
    reset_ep="$latest_reset"
  elif [ -n "$latest_reset" ] && [ "$latest_reset" != "null" ] && reset_ep="$(iso_to_epoch "$latest_reset" 2>/dev/null)"; then
    :
  else
    reset_ep=$(( last_ts_ep + 86400 ))
  fi
  window_start=$(( reset_ep - 7 * 86400 ))

  { echo "hours,actual,pace"
    jq -r '.[] | [.ts, .seven_day] | @tsv' <<<"$cycle" | while IFS=$'\t' read -r ts sd; do
      ep="$(iso_to_epoch "$ts")" || continue
      awk -v ep="$ep" -v ws="$window_start" -v sd="$sd" 'BEGIN{h=(ep-ws)/3600; printf "%.1f,%.1f,%.1f\n", h, sd, 100*h/168}'
    done
  } | uplot lines -d ',' -H --fmt xyy -t "Weekly usage vs. limit" --xlabel "hours into 7-day window" --ylabel "% of weekly limit"

  # Project current burn rate forward to the reset.
  local first_ts first_sd last_sd first_ep dt_h
  first_ts="$(jq -r '.[0].ts' <<<"$cycle")"
  first_sd="$(jq -r '.[0].seven_day' <<<"$cycle")"
  last_sd="$(jq -r '.[-1].seven_day' <<<"$cycle")"
  first_ep="$(iso_to_epoch "$first_ts")"
  dt_h="$(awk -v a="$first_ep" -v b="$last_ts_ep" 'BEGIN{print (b-a)/3600}')"
  if awk "BEGIN{exit !(${dt_h}>0)}"; then
    local projected verdict
    projected="$(awk -v cur="$last_sd" -v fs="$first_sd" -v dt="$dt_h" -v rr="$reset_ep" -v lt="$last_ts_ep" 'BEGIN{slope=(cur-fs)/dt; print cur+slope*((rr-lt)/3600)}')"
    verdict="$(awk -v p="$projected" 'BEGIN{print (p>=100)?"projected to hit the weekly limit before reset":"on track to stay under"}')"
    printf '  now %.1f%%  ·  projected at reset %.1f%%  ·  %s\n' "$last_sd" "$projected" "$verdict"
    printf '  reset %s\n' "$(epoch_to_disp "$reset_ep")"
  else
    printf '  now %.1f%% of weekly limit\n' "$last_sd"
  fi
}

# --- Help ---
cmd_pace_help() {
  echo "Pacing / burndown charts:"
  echo "  claude-usage pace week   - Usage vs. the weekly limit (authoritative % from the statusline log)"
  echo "  claude-usage pace week --proxy   - ccusage cost view of the last 7 days (works today)"
  echo "  claude-usage pace month  - Cumulative cost this month vs. a pace line"
  echo ""
  echo "Options:"
  echo "  --proxy         (week) cost-based view instead of the logged weekly-limit %"
  echo "  --ceiling N     (week --proxy) reference ceiling USD (default: prior 7-day total)"
  echo "  --budget N      (month) reference ceiling USD (default: previous month's total)"
  echo "  --tokens        (month) chart total tokens instead of USD"
}
cmd_help() {
  echo "Claude Usage Analytics"
  echo ""
  echo "Commands:"
  echo "  claude-usage daily   - Daily cost chart"
  echo "  claude-usage weekly  - Weekly cost chart"
  echo "  claude-usage monthly - Monthly cost chart"
  echo "  claude-usage sessions - Top sessions by cost"
  echo "  claude-usage blocks  - 5-hour billing blocks"
  echo "  claude-usage pace week  - Burndown vs. the weekly usage limit"
  echo "  claude-usage pace month - Cumulative cost this month vs. pace"
  echo "  claude-usage status  - Current 5-hour block status"
  echo ""
  echo "Options:"
  echo "  --days N    - Number of days (daily, default: 30)"
  echo "  --weeks N   - Number of weeks (weekly, default: 12)"
  echo "  --months N  - Number of months (monthly, default: 6)"
  echo "  --limit N   - Number of sessions (sessions, default: 20)"
  echo "  (run 'claude-usage pace' for pacing-chart options)"
}

# --- Dispatch ---
main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    daily)           cmd_daily "$@";;
    weekly)          cmd_weekly "$@";;
    monthly)         cmd_monthly "$@";;
    sessions)        cmd_sessions "$@";;
    blocks)          cmd_blocks "$@";;
    status)          cmd_status "$@";;
    refresh-pricing) cmd_refresh_pricing "$@";;
    pace)
      local sub="${1:-}"; shift || true
      case "$sub" in
        week)      cmd_pace_week "$@";;
        month)     cmd_pace_month "$@";;
        ""|help)   cmd_pace_help;;
        *) echo "Unknown: pace ${sub}" >&2; cmd_pace_help; return 1;;
      esac;;
    ""|help|-h|--help) cmd_help;;
    *) echo "Unknown command: ${cmd}" >&2; cmd_help; return 1;;
  esac
}
main "$@"
