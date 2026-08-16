#!/usr/bin/env bash
# Claude Usage Analytics — CLI tool
# Analyzes Claude Code usage data and displays cost/usage & pacing charts.
#
# Engines: duckdb (aggregation), ccusage (pacing, current pricing), uplot/youplot
# (charts), jq. No nushell dependency — the SQL models in ./models/ are unchanged.
set -uo pipefail

# --- Configuration ---
CLAUDE_USAGE_DIR="${HOME}/.config/analysis/claude-usage"
DATA_DIR="${CLAUDE_USAGE_DIR}/data"
MODELS_DIR="${CLAUDE_USAGE_DIR}/models"
DB_PATH="${DATA_DIR}/usage.db"
PRICING_CACHE="${DATA_DIR}/pricing.json"
PRICING_CSV="${DATA_DIR}/pricing.csv"
PRICING_URL="https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
PRICING_CACHE_HOURS=24
LIMITS_LOG="${DATA_DIR}/limits-log.jsonl"
# Authoritative usage meters from /api/oauth/usage (see ~/.local/bin/cc-usage-fetch).
USAGE_API_CACHE="${DATA_DIR}/usage-api.json"
USAGE_HISTORY="${DATA_DIR}/usage-log.jsonl"
USAGE_FETCH="${HOME}/.local/bin/cc-usage-fetch"
USAGE_CACHE_TTL=1200   # 20 min — the endpoint is heavily rate-limited

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

# Convert a timestamp to epoch seconds. Accepts a Unix epoch int (status-line
# resets_at), an ISO8601 …Z (our log ts), or ISO with fractional secs + offset
# (the API resets_at). All treated as UTC.
any_to_epoch() {
  local v="$1" s e
  case "$v" in
    ''|null) return 1;;
    *[!0-9]*)  # non-digits -> ISO; strip fractional secs and any trailing offset/Z
      s="$(printf '%s' "$v" | sed -E 's/\.[0-9]+//; s/([+-][0-9]{2}):?[0-9]{2}$//; s/Z$//')"
      e=$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "$s" +%s 2>/dev/null) && { printf '%s' "$e"; return; }
      e=$(date -u -d "$v" +%s 2>/dev/null) && { printf '%s' "$e"; return; }
      return 1;;
    *) printf '%s' "$v";;  # already an epoch
  esac
}
epoch_to_disp() { date -r "$1" +'%a %d %b %H:%M' 2>/dev/null || date -d "@$1" +'%a %d %b %H:%M'; }
# Humanize a positive second-count as "1h 41m" / "41m" / "12h".
fmt_reltime() {
  local s="$1" h m
  [ "$s" -lt 0 ] && s=0
  h=$(( s / 3600 )); m=$(( (s % 3600) / 60 ))
  if [ "$h" -gt 0 ] && [ "$m" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
  elif [ "$h" -gt 0 ]; then printf '%dh' "$h"
  else printf '%dm' "$m"; fi
}

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
# Boxed output for multi-column tables — the chart commands use CSV + uplot,
# but these are small tables meant to be read rather than plotted.
table_db() { printf '%s' "$1" | duckdb -init /dev/null -box "$DB_PATH"; }

# `mix` — where the output tokens went, on the two axes `cwd` cannot answer.
# It REPORTS; it sets no target. A spend ratio is an INPUT measure and the most
# gameable class there is: verbose code and terse notes would "improve" every
# number here while making the work worse. Read it as a diagnostic.
cmd_mix() {
  local weeks; weeks="$(get_flag_val --weeks "$@")"; weeks="${weeks:-6}"
  build_db

  echo
  echo "  WHO SPENT IT — main loop vs subagents"
  echo "  conductor% is the share of output tokens spent in the main loop rather than"
  echo "  in a builder, verifier or triage agent — the closest available proxy for"
  echo "  orchestration overhead measured against work delivered."
  table_db "
    SELECT strftime('%Y-%m-%d', event_week) AS week,
           SUM(CASE WHEN NOT is_sidechain THEN output_tokens ELSE 0 END) AS conductor,
           SUM(CASE WHEN is_sidechain THEN output_tokens ELSE 0 END)     AS subagent,
           ROUND(100.0 * SUM(CASE WHEN NOT is_sidechain THEN output_tokens ELSE 0 END)
                 / NULLIF(SUM(output_tokens), 0), 1) AS \"conductor%\"
    FROM fact_usage GROUP BY 1 ORDER BY 1 DESC LIMIT ${weeks};"

  echo
  echo "  CONTEXT AMPLIFICATION — context re-read per token written"
  echo "  read/out rising against flat output means the same context is being re-read"
  echo "  to produce the same work. reuse% is cache reads as a share of all cached"
  echo "  input; a low reuse% means paying to rebuild cache that was just discarded."
  table_db "
    SELECT strftime('%Y-%m-%d', event_week) AS week,
           SUM(output_tokens)         AS output,
           SUM(cache_read_tokens)     AS cache_read,
           SUM(cache_creation_tokens) AS cache_created,
           ROUND(SUM(cache_read_tokens) * 1.0 / NULLIF(SUM(output_tokens), 0), 1) AS \"read/out\",
           ROUND(100.0 * SUM(cache_read_tokens)
                 / NULLIF(SUM(cache_read_tokens) + SUM(cache_creation_tokens), 0), 1) AS \"reuse%\"
    FROM fact_usage GROUP BY 1 ORDER BY 1 DESC LIMIT ${weeks};"

  echo
  echo "  WHERE — output tokens by working directory"
  table_db "
    SELECT regexp_extract(working_directory, '([^/]+)/?\$', 1) AS dir,
           SUM(output_tokens) AS output,
           COUNT(*) AS requests
    FROM fact_usage
    WHERE event_week >= (SELECT MAX(event_week) FROM fact_usage) - INTERVAL '${weeks} weeks'
    GROUP BY 1 HAVING SUM(output_tokens) > 0 ORDER BY 2 DESC LIMIT 12;"
  echo
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

# Current authoritative usage snapshot from /api/oauth/usage: prefer a fresh
# cache, else best-effort fetch (which no-ops on the endpoint's frequent 429),
# else the last good cache. Empty when the API has never succeeded.
usage_snapshot() {
  local now; now="$(date +%s)"
  if [ -f "$USAGE_API_CACHE" ]; then
    local age
    age=$(( now - $(stat -f %m "$USAGE_API_CACHE" 2>/dev/null || stat -c %Y "$USAGE_API_CACHE" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$USAGE_CACHE_TTL" ] && { cat "$USAGE_API_CACHE"; return 0; }
  fi
  # Throttle fetch *attempts* to once per TTL: the endpoint 429s, and each try
  # touches the Keychain — don't do that on every command.
  local stamp="${DATA_DIR}/.usage-fetch.attempt" last=0
  [ -f "$stamp" ] && last="$(stat -f %m "$stamp" 2>/dev/null || stat -c %Y "$stamp" 2>/dev/null || echo 0)"
  if [ -x "$USAGE_FETCH" ] && [ $(( now - last )) -ge "$USAGE_CACHE_TTL" ]; then
    mkdir -p "$DATA_DIR"; : > "$stamp"
    "$USAGE_FETCH" >/dev/null 2>&1 || true
  fi
  [ -f "$USAGE_API_CACHE" ] && { cat "$USAGE_API_CACHE"; return 0; }
  return 1
}

# Cleaned all-models weekly series from the status-line log: current cycle only,
# per-10-min-bucket median (rejects the minority stale/outlier session reads).
# Emits "epoch<TAB>value" rows, sorted. Used as the historical curve and as the
# fallback current value when the API is unavailable.
clean_statusline_series() {
  [ -f "$LIMITS_LOG" ] || return 1
  grep '^{.*}$' "$LIMITS_LOG" 2>/dev/null | jq -rs '
    def median(f): (map(f) | sort) as $s | $s[(($s|length)/2|floor)];
    [ .[] | select(.seven_day != null and .ts != null)
          | {te: (.ts | fromdateiso8601), v: .seven_day, r: (.resets_at // 0)} ]
    | if length == 0 then empty else
        (max_by(.r).r) as $c
        | map(select(.r == $c))
        | group_by((.te / 600) | floor)
        | map({te: (map(.te) | min), v: (median(.v))})
        | sort_by(.te)
        # The all-models weekly only climbs, so no earlier point can exceed the
        # current value — drop stale single-session spikes above it (+2 slack).
        | (.[-1].v) as $last
        | map(select(.v <= $last + 2))
        | .[] | [.te, .v] | @tsv
      end'
}

# `ccu usage` — current plan-usage meters, like the desktop /usage panel.
cmd_usage() {
  local snap; snap="$(usage_snapshot || true)"
  if [ -z "$snap" ] || [ "$snap" = "null" ]; then
    local series v
    series="$(clean_statusline_series 2>/dev/null)"
    if [ -z "$series" ]; then echo "No usage data (API rate-limited, no status-line log yet)."; return; fi
    v="$(printf '%s\n' "$series" | tail -1 | cut -f2)"
    echo "Plan usage limits   (status-line fallback — /api/oauth/usage rate-limited)"
    echo "Weekly limits"
    printf '  %-15s %4s%%   (all models; per-model sub-limit needs the API)\n' "All models" "$v"
    return
  fi

  local now snap_ep
  now="$(date +%s)"
  snap_ep="$(any_to_epoch "$(jq -r '.ts' <<<"$snap")")"
  printf 'Plan usage limits   (/api/oauth/usage, %s ago)\n' "$(fmt_reltime $(( now - ${snap_ep:-now} )))"

  local su sr
  su="$(jq -r '.session.util // empty' <<<"$snap")"
  sr="$(any_to_epoch "$(jq -r '.session.resets_at // empty' <<<"$snap")")"
  [ -n "$su" ] && printf '  %-15s %4s%%   resets in %s\n' "Current session" "$su" "$(fmt_reltime $(( ${sr:-now} - now )))"

  echo "Weekly limits"
  local wu wr
  wu="$(jq -r '.weekly_all.util // empty' <<<"$snap")"
  wr="$(any_to_epoch "$(jq -r '.weekly_all.resets_at // empty' <<<"$snap")")"
  [ -n "$wu" ] && printf '  %-15s %4s%%   resets %s\n' "All models" "$wu" "$(epoch_to_disp "${wr:-0}")"
  jq -r '.weekly_models[]? | [.name, (.util|tostring), (.resets_at // "")] | @tsv' <<<"$snap" \
    | while IFS=$'\t' read -r name util rst; do
        local nm rep
        nm="$(printf '%s' "$name" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
        rep="$(any_to_epoch "$rst")"
        printf '  %-15s %4s%%   resets %s\n' "$nm" "$util" "$(epoch_to_disp "${rep:-0}")"
      done
}

# Rebuild the DuckDB only if missing or older than $1 seconds (keeps repeated
# `pace week` runs snappy while staying reasonably current).
ensure_db() {
  local max="${1:-0}" age
  if [ -f "$DB_PATH" ] && [ "$max" -gt 0 ]; then
    age=$(( $(date +%s) - $(stat -f %m "$DB_PATH" 2>/dev/null || stat -c %Y "$DB_PATH" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$max" ] && return 0
  fi
  echo "  (rebuilding usage db from transcripts…)" >&2
  build_db >&2
}

# Exact hourly cumulative cost since window_start (epoch $1), from fact_usage.
# Emits "days_into_window<TAB>cumcost". Honors the precise mid-day reset boundary,
# unlike ccusage's calendar-day buckets. Used to reconstruct the weekly-% shape
# for days the status-line log didn't cover.
cost_curve_db() {
  local ws="$1" ws_utc
  ws_utc="$(date -u -r "$ws" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -u -d "@$ws" '+%Y-%m-%d %H:%M:%S')"
  query_db "WITH h AS (SELECT date_trunc('hour', event_timestamp) AS hr, SUM(cost_usd) AS c FROM fact_usage WHERE event_timestamp >= TIMESTAMP '${ws_utc}' GROUP BY 1) SELECT ROUND((epoch(hr) - ${ws})/86400.0, 4) AS day, ROUND(SUM(c) OVER (ORDER BY hr), 4) AS cum FROM h ORDER BY hr" \
    | tail -n +2 | tr ',' '\t'
}

# Immutable weekly-% history from the authoritative API log (usage-log.jsonl):
# each row is a real value recorded at a real time, so re-plotting never moves the
# past — unlike the cost reconstruction, which re-derives every point from the
# current total and so "breathes" as cur/total drift. Current cycle only
# (ts >= window_start), collapsed to per-10-min buckets taking the max (the weekly
# counter only ever climbs). Emits "day<TAB>pct" at hourly resolution (matches the
# old cost curve's granularity — fine enough for shape, coarse enough to stay clean).
logged_pct_series() {
  local ws="$1"
  [ -f "$USAGE_HISTORY" ] || return 1
  grep '^{' "$USAGE_HISTORY" 2>/dev/null | jq -rs --argjson ws "$ws" '
    [ .[] | select(.ts != null and .weekly_all != null and .weekly_all.util != null)
          | {t: (.ts | fromdateiso8601), v: .weekly_all.util} ]
    | map(select(.t >= $ws)) | sort_by(.t)
    | group_by((.t / 3600) | floor) | map({t: (map(.t) | max), v: (map(.v) | max)})
    | .[] | [ ((.t - $ws) / 86400), .v ] | @tsv'
}

# Turn a "day<TAB>pct" series (stdin) into the pace-delta chart CSV
# (day,ahead,on-pace): anchor at (0,0) — the counter is 0% at reset — plot
# delta = pct − on-pace(day), clamp day to now_day, then append the idle tail
# (usage held flat to now_day) so the curve reaches "now" and lands on the topline.
build_delta_csv() {  # $1=now_day  $2=cur  ; "day<TAB>pct" series on stdin
  local nd="$1" cur="$2"
  echo "day,ahead,on-pace"; echo "0,0,0"
  awk -F'\t' -v nd="$nd" '{ d=$1; if(d>nd)d=nd; if(d>0.01) printf "%.3f,%.2f,0\n", d, $2 - 100*d/7 }'
  awk -v c="$cur" -v nd="$nd" 'BEGIN{ if (nd>0.01) printf "%.3f,%.2f,0\n", nd, c - 100*nd/7 }'
}

# Weekly burndown vs. the usage limit. Current value + reset (+ per-model
# sub-limits) come from the authoritative API snapshot (statusline fallback). The
# historical curve is the RECORDED weekly % over time (immutable — the past never
# changes on refresh); cost reconstruction is only a last resort. --proxy = ccusage.
cmd_pace_week() {
  if has_flag --proxy "$@"; then pace_week_proxy "$(get_flag_val --ceiling "$@")"; return; fi

  local now snap cur reset_ep source_label series
  now="$(date +%s)"
  snap="$(usage_snapshot || true)"
  series="$(clean_statusline_series 2>/dev/null)"

  if [ -n "$snap" ] && [ "$snap" != "null" ] && [ -n "$(jq -r '.weekly_all.util // empty' <<<"$snap")" ]; then
    cur="$(jq -r '.weekly_all.util' <<<"$snap")"
    reset_ep="$(any_to_epoch "$(jq -r '.weekly_all.resets_at' <<<"$snap")")"
    source_label="api"
  elif [ -n "$series" ]; then
    cur="$(printf '%s\n' "$series" | tail -1 | cut -f2)"
    reset_ep="$(grep '^{.*}$' "$LIMITS_LOG" 2>/dev/null | jq -rs 'map(select(.seven_day!=null))|(max_by(.resets_at//0).resets_at // empty)')"
    reset_ep="$(any_to_epoch "$reset_ep")" || reset_ep=$(( now + 86400 ))
    source_label="status-line (cleaned)"
  else
    echo "No weekly-limit data yet."
    echo "  /api/oauth/usage is rate-limited and no status-line samples exist."
    echo "  Deterministic alternative:  ccu pace week --proxy   (ccusage cost)"
    return
  fi
  local window_start=$(( reset_ep - 7 * 86400 ))

  # Plot how far we're AHEAD / BEHIND the on-pace line (weekly% − ideal-pace%)
  # across the week. Both axes auto-scale so a few points of drift fill the frame;
  # the flat 0 series is the on-pace reference — above it = over-pacing.
  local ws_disp reset_disp now_day curve_note
  ws_disp="$(date -r "$window_start" +'%a %d %b' 2>/dev/null || date -d "@$window_start" +'%a %d %b')"
  reset_disp="$(date -r "$reset_ep" +'%a %d %b' 2>/dev/null || date -d "@$reset_ep" +'%a %d %b')"
  now_day="$(awk -v n="$now" -v ws="$window_start" 'BEGIN{printf "%.4f",(n-ws)/86400}')"

  # Pick the %-history source, best (immutable) first:
  #   1. recorded weekly % from the API log — the past is FIXED, never re-derived.
  #   2. cleaned status-line % — also recorded/immutable, just noisier.
  #   3. cost reconstruction — back-calibrated to the current %, so the past
  #      "breathes" as cur/total drift; only when no % history exists yet. It needs
  #      the DuckDB, so we build it lazily here rather than on every run.
  local hist hist_n pct_series cost_rows total factor chart_csv
  hist="$(logged_pct_series "$window_start" 2>/dev/null)"
  hist_n="$(printf '%s' "$hist" | grep -c .)"

  if [ "$hist_n" -ge 3 ]; then
    pct_series="$hist"
    curve_note="  curve: recorded weekly % (API history — the past is fixed)"
  elif [ -n "$series" ]; then
    pct_series="$(printf '%s\n' "$series" | awk -F'\t' -v ws="$window_start" '{printf "%.4f\t%s\n",($1-ws)/86400,$2}')"
    curve_note="  curve: status-line % history (cleaned)"
  else
    ensure_db 900
    cost_rows="$(cost_curve_db "$window_start" 2>/dev/null)"
    total="$(printf '%s\n' "$cost_rows" | tail -1 | cut -f2)"
    if [ -n "$cost_rows" ] && awk "BEGIN{exit !(${total:-0}>0)}"; then
      factor="$(awk -v c="$cur" -v t="$total" 'BEGIN{print c/t}')"
      pct_series="$(printf '%s\n' "$cost_rows" | awk -F'\t' -v f="$factor" '{printf "%s\t%.4f\n",$1,$2*f}')"
      curve_note="  curve: estimated from usage cost, anchored to ${cur}% (no % history yet)"
    else
      pct_series=""
      curve_note="  curve: (not enough data yet)"
    fi
  fi

  chart_csv="$(build_delta_csv "$now_day" "$cur" <<<"$pct_series")"
  printf '%s\n' "$chart_csv" | uplot lines -d ',' -H --fmt xyy \
        -t "Weekly pace — points ahead of / behind pace" \
        --xlabel "days into week ($ws_disp → $reset_disp)" --ylabel "points ahead of pace"

  # Deterministic pace + projection from the current value and elapsed fraction.
  local frac projected pace_pct pace_note
  frac="$(awk -v n="$now" -v ws="$window_start" 'BEGIN{print (n-ws)/604800}')"
  pace_pct="$(awk -v f="$frac" 'BEGIN{print f*100}')"
  projected="$(awk -v c="$cur" -v f="$frac" 'BEGIN{ if (f<=0) print c; else print c/f }')"
  # How far ahead/behind the on-pace line, in limit-points — ties to the chart's y.
  pace_note="$(awk -v c="$cur" -v p="$pace_pct" 'BEGIN{ d=c-p; ad=(d<0)?-d:d; if (ad<0.5) printf "on pace"; else if (d>0) printf "%.0f pts ahead of pace", ad; else printf "%.0f pts behind pace", ad }')"
  printf '  now %s%%  ·  ideal pace %.0f%%  ·  pacing at %.0f%%  ·  %s\n' "$cur" "$pace_pct" "$projected" "$pace_note"
  printf '  reset %s  ·  source: %s\n' "$(epoch_to_disp "$reset_ep")" "$source_label"
  [ -n "${curve_note:-}" ] && printf '%s\n' "$curve_note"

  if [ -n "$snap" ] && [ "$snap" != "null" ]; then
    jq -r '.weekly_models[]? | "  \(.name) sub-limit: \(.util)%"' <<<"$snap" 2>/dev/null
  fi
}

# --- Help ---
cmd_pace_help() {
  echo "Pacing / burndown charts:"
  echo "  claude-usage usage       - Current plan-usage meters (session + weekly, like the app)"
  echo "  claude-usage pace week   - Burndown vs. the weekly limit (API-preferred, statusline fallback)"
  echo "  claude-usage pace week --proxy   - ccusage cost view of the last 7 days (fully deterministic)"
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
  echo "  claude-usage mix     - Conductor vs subagent spend, and context re-read per token"
  echo "  claude-usage usage   - Current plan-usage meters (like the desktop /usage panel)"
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
    mix)             cmd_mix "$@";;
    status)          cmd_status "$@";;
    usage)           cmd_usage "$@";;
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
