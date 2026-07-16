#!/usr/bin/env nu

# Claude Usage Analytics - CLI Tool
# Analyzes Claude Code usage data and displays cost/usage charts

# Configuration
const CLAUDE_USAGE_DIR = "~/.config/nushell/analysis/claude-usage"
const DB_PATH = $"($CLAUDE_USAGE_DIR)/data/usage.db"
const PRICING_CACHE = $"($CLAUDE_USAGE_DIR)/data/pricing.json"
const PRICING_CSV = $"($CLAUDE_USAGE_DIR)/data/pricing.csv"
const PRICING_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
const PRICING_CACHE_HOURS = 24
# Append-only log of the authoritative weekly-limit % sampled by the statusline
# hook (~/.local/bin/cc-limits-log). Source of truth for `pace week`.
const LIMITS_LOG = $"($CLAUDE_USAGE_DIR)/data/limits-log.jsonl"

# Determine JSONL glob patterns based on CLAUDE_CONFIG_DIR
def get-jsonl-globs []: nothing -> list<string> {
    if ($env.CLAUDE_CONFIG_DIR? | is-not-empty) {
        $env.CLAUDE_CONFIG_DIR | split row ',' | each { |dir| $"($dir | path expand)/projects/**/*.jsonl" }
    } else {
        [
            ("~/.config/claude/projects/**/*.jsonl" | path expand),
            ("~/.claude/projects/**/*.jsonl" | path expand)
        ]
    }
}

# Check if pricing cache is valid (less than 24 hours old)
def pricing-cache-valid []: nothing -> bool {
    let cache_path = ($PRICING_CACHE | path expand)
    if not ($cache_path | path exists) {
        return false
    }
    let modified = ($cache_path | path expand | ls $in | get 0.modified)
    let age_hours = ((date now) - $modified) / 1hr
    $age_hours < $PRICING_CACHE_HOURS
}

# Fetch and cache pricing data
def fetch-pricing [--force] {
    let cache_path = ($PRICING_CACHE | path expand)
    let csv_path = ($PRICING_CSV | path expand)

    if (not $force) and (pricing-cache-valid) {
        return
    }

    print "Fetching pricing data..."
    let pricing_json = (http get $PRICING_URL)
    $pricing_json | save -f $cache_path

    # Preprocess into CSV for DuckDB.
    # Dynamically select every first-party Anthropic Claude model from the
    # LiteLLM feed (litellm_provider == "anthropic"), keyed on the bare model
    # id — which is exactly what Claude Code writes to its transcripts. This
    # auto-covers new models (opus-4-8, sonnet-5, fable-5, …) instead of the
    # old hardcoded allowlist, which silently priced anything newer at $0.
    print "Processing pricing data..."
    let pricing_records = (
        $pricing_json
        | transpose model_name spec
        | where {|r| ($r.spec | describe | str starts-with "record") }
        | where {|r| ($r.spec | get -o litellm_provider) == "anthropic" }
        | where {|r| $r.model_name | str starts-with "claude" }
        | each {|r|
            {
                model_name: $r.model_name
                input_cost_per_token: ($r.spec | get -o input_cost_per_token | default 0)
                output_cost_per_token: ($r.spec | get -o output_cost_per_token | default 0)
                cache_creation_cost_per_token: ($r.spec | get -o cache_creation_input_token_cost | default 0)
                cache_read_cost_per_token: ($r.spec | get -o cache_read_input_token_cost | default 0)
            }
        }
    )

    $pricing_records | to csv | save -f $csv_path
    print $"Pricing data cached \(($pricing_records | length) Claude models\)."
}

# Build a DuckDB-compatible glob pattern from multiple paths
def build-jsonl-glob []: nothing -> string {
    let globs = (get-jsonl-globs)

    # Find files matching each glob and return as list
    let files = ($globs | each { |g|
        try { glob $g } catch { [] }
    } | flatten)

    if ($files | is-empty) {
        error make { msg: "No JSONL files found in any configured path" }
    }

    # Return as a list pattern for DuckDB
    $files | to json
}

# Run a SQL model file with parameter substitution
def run-sql [sql_file: string, params: record = {}] {
    let sql_path = ($"($CLAUDE_USAGE_DIR)/models/($sql_file)" | path expand)
    let db_path = ($DB_PATH | path expand)

    mut sql = (open $sql_path)

    # Substitute parameters
    for key in ($params | columns) {
        let value = ($params | get $key)
        $sql = ($sql | str replace --all $"$($key)" $value)
    }

    # Execute SQL
    $sql | duckdb $db_path
}

# Build the complete database from JSONL files
def build-db [] {
    let db_path = ($DB_PATH | path expand)
    let data_dir = ($"($CLAUDE_USAGE_DIR)/data" | path expand)

    # Ensure data directory exists
    mkdir $data_dir

    # Remove existing database
    if ($db_path | path exists) {
        rm -f $db_path
    }

    # Fetch pricing if needed
    fetch-pricing

    # Get JSONL file list
    let jsonl_glob = (build-jsonl-glob)

    # Change to data directory for relative paths in SQL
    cd $data_dir

    # Get pricing CSV path
    let pricing_csv_path = ($PRICING_CSV | path expand)

    # Run all model files in order
    run-sql "01_load_data.sql" { jsonl_glob: $jsonl_glob }
    run-sql "02_staging.sql"
    run-sql "03_pricing.sql" { pricing_csv_path: $"'($pricing_csv_path)'" }
    run-sql "04_usage_facts.sql"
    run-sql "05_aggregates.sql"
    run-sql "06_sessions.sql"
    run-sql "07_billing_blocks.sql"

    # Surface any models present in the data but missing from pricing — they are
    # counted at $0 and would silently understate cost. '<synthetic>' rows are
    # expected placeholders with no real spend and are excluded.
    let unpriced = (
        query-db "SELECT DISTINCT model_name FROM stg_usage WHERE model_name NOT IN (SELECT model_name FROM dim_pricing) AND model_name NOT LIKE '<%>' ORDER BY model_name"
        | from csv
        | get -o model_name
        | default []
    )
    if ($unpriced | is-not-empty) {
        print $"⚠  ($unpriced | length) model\(s\) in your data have no pricing \(counted at $0\):"
        for m in $unpriced { print $"     - ($m)" }
        print "   Re-run 'ccu refresh-pricing' once LiteLLM lists them, or check the model id."
    }
}

# Query database and return CSV
def query-db [sql: string]: nothing -> string {
    let db_path = ($DB_PATH | path expand)
    $sql | duckdb -csv $db_path
}

# ---------------------------------------------------------------------------
# Pacing / burndown charts (ccusage + youplot)
# ---------------------------------------------------------------------------

# Run ccusage (an npm package) via bunx/npx and return its parsed JSON. ccusage
# stays in sync with LiteLLM pricing and handles current models correctly, so it
# is the data source for the pacing charts — kept independent of the DuckDB bars.
def ccusage [args: list<string>]: nothing -> any {
    let base = if (which bunx | is-not-empty) {
        [bunx ccusage@latest]
    } else if (which npx | is-not-empty) {
        [npx --yes ccusage@latest]
    } else {
        error make { msg: "ccusage needs 'bunx' or 'npx' on PATH — install bun (brew install bun) or node" }
    }
    let argv = ($base | append $args)
    # `complete` captures stderr so bunx/npx dependency-resolution chatter stays
    # quiet on success, and surfaces it only when ccusage actually fails.
    let result = (run-external ($argv | first) ...($argv | skip 1) | complete)
    if $result.exit_code != 0 {
        error make { msg: $"ccusage failed \(exit ($result.exit_code)\): ($result.stderr | str trim)" }
    }
    $result.stdout | from json
}

# ccusage --since / --until want a YYYYMMDD string.
def fmt-since [dt: datetime]: nothing -> string { $dt | format date "%Y%m%d" }

# Midnight on the first of the current calendar month.
def month-start []: nothing -> datetime {
    (date now | format date "%Y-%m-01") + "T00:00:00" | into datetime
}

# Number of days in the current calendar month.
def days-in-month []: nothing -> int {
    let ms = (month-start)
    let next = (($ms + 32day) | format date "%Y-%m-01") + "T00:00:00" | into datetime
    (($next - $ms) / 1day | math round)
}

# ccusage daily rows (period + totalCost + totalTokens) since a YYYYMMDD string.
def ccusage-daily [since: string]: nothing -> table {
    ccusage ["daily" "--json" "--since" $since]
    | get daily
    | select period totalCost totalTokens
    | sort-by period
}

# Total cost (or tokens) for the previous calendar month — default month ref line.
def last-month-total [tokens: bool]: nothing -> float {
    let prev_end = ((month-start) - 1day)
    let metric = if $tokens { "totalTokens" } else { "totalCost" }
    let rows = (ccusage ["daily" "--json" "--since" ($prev_end | format date "%Y%m01") "--until" ($prev_end | format date "%Y%m%d")] | get daily)
    if ($rows | is-empty) { 0.0 } else { $rows | get $metric | math sum | into float }
}

# Total cost for the 7 days before the current 7-day window — default week ref.
def prior-7day-total []: nothing -> float {
    let rows = (ccusage ["daily" "--json" "--since" (fmt-since ((date now) - 14day)) "--until" (fmt-since ((date now) - 7day))] | get daily)
    if ($rows | is-empty) { 0.0 } else { $rows | get totalCost | math sum | into float }
}

# Render a two-series (actual vs pace) line chart from a table whose columns are
# ordered [x, actual, pace]. youplot `lines --fmt xyy -H` names each series from
# its y-column header.
def render-pace [data: table, title: string, xlabel: string, ylabel: string] {
    if (($data | length) < 2) {
        print $"Not enough data points to chart yet \(have ($data | length), need 2+\)."
        return
    }
    $data | to csv | uplot lines -d ',' -H --fmt xyy -t $title --xlabel $xlabel --ylabel $ylabel
}

# Tail of the samples starting at the last sharp drop in the 7-day %, which
# marks a weekly reset. Used only when no resets_at timestamp is available.
def cut-at-last-reset [wk: table]: nothing -> table {
    let n = ($wk | length)
    mut start = 0
    for i in 1..($n - 1) {
        let prev = ($wk | get ($i - 1) | get seven_day | into float)
        let cur = ($wk | get $i | get seven_day | into float)
        if $cur < ($prev - 20) { $start = $i }
    }
    $wk | skip $start
}

# Main entry point
def main [] {
    print "Claude Usage Analytics"
    print ""
    print "Commands:"
    print "  claude-usage daily   - Daily cost chart"
    print "  claude-usage weekly  - Weekly cost chart"
    print "  claude-usage monthly - Monthly cost chart"
    print "  claude-usage sessions - Top sessions by cost"
    print "  claude-usage blocks  - 5-hour billing blocks"
    print "  claude-usage pace week  - Burndown vs. the weekly usage limit"
    print "  claude-usage pace month - Cumulative cost this month vs. pace"
    print "  claude-usage status  - Current 5-hour block status"
    print ""
    print "Options:"
    print "  --days N    - Number of days (daily, default: 30)"
    print "  --weeks N   - Number of weeks (weekly, default: 12)"
    print "  --months N  - Number of months (monthly, default: 6)"
    print "  --limit N   - Number of sessions (sessions, default: 20)"
    print "  (run 'claude-usage pace' for pacing-chart options)"
}

# Daily cost chart
def "main daily" [
    --days: int = 30  # Number of days to show
] {
    build-db

    let sql = $"SELECT strftime\('%Y-%m-%d', event_date\) as date, ROUND\(cost_usd, 4\) as cost
                FROM agg_daily
                ORDER BY event_date DESC
                LIMIT ($days)"

    query-db $sql
        | from csv
        | reverse
        | to csv --noheaders
        | uplot bar -d ',' -t $"Daily Cost \(Last ($days) Days\)" --ylabel "USD"
}

# Weekly cost chart
def "main weekly" [
    --weeks: int = 12  # Number of weeks to show
] {
    build-db

    let sql = $"SELECT strftime\('%Y-%m-%d', event_week\) as week, ROUND\(cost_usd, 4\) as cost
                FROM agg_weekly
                ORDER BY event_week DESC
                LIMIT ($weeks)"

    query-db $sql
        | from csv
        | reverse
        | to csv --noheaders
        | uplot bar -d ',' -t $"Weekly Cost \(Last ($weeks) Weeks\)" --ylabel "USD"
}

# Monthly cost chart
def "main monthly" [
    --months: int = 6  # Number of months to show
] {
    build-db

    let sql = $"SELECT strftime\('%Y-%m', event_month\) as month, ROUND\(cost_usd, 4\) as cost
                FROM agg_monthly
                ORDER BY event_month DESC
                LIMIT ($months)"

    query-db $sql
        | from csv
        | reverse
        | to csv --noheaders
        | uplot bar -d ',' -t $"Monthly Cost \(Last ($months) Months\)" --ylabel "USD"
}

# Top sessions by cost
def "main sessions" [
    --limit: int = 20  # Number of sessions to show
] {
    build-db

    let sql = $"SELECT
                    LEFT\(session_id::VARCHAR, 8\) as session,
                    ROUND\(cost_usd, 4\) as cost
                FROM agg_sessions
                ORDER BY cost_usd DESC
                LIMIT ($limit)"

    query-db $sql
        | from csv
        | reverse
        | to csv --noheaders
        | uplot barplot -d ',' -t $"Top ($limit) Sessions by Cost" --ylabel "USD"
}

# 5-hour billing blocks
def "main blocks" [
    --limit: int = 20  # Number of blocks to show
] {
    build-db

    let sql = $"SELECT
                    block_id as block,
                    ROUND\(cost_usd, 4\) as cost
                FROM agg_billing_blocks
                ORDER BY block_start DESC
                LIMIT ($limit)"

    query-db $sql
        | from csv
        | reverse
        | to csv --noheaders
        | uplot bar -d ',' -t $"Recent 5-Hour Billing Blocks" --ylabel "USD"
}

# Show current block status
def "main status" [] {
    build-db

    let sql = "SELECT
                block_id,
                strftime('%Y-%m-%d %H:%M', block_start) as started,
                message_count,
                ROUND(cost_usd, 4) as cost_usd,
                is_active,
                ROUND(hours_remaining, 2) as hours_left
               FROM agg_billing_blocks
               ORDER BY block_start DESC
               LIMIT 1"

    let result = (query-db $sql | from csv)

    if ($result | is-empty) {
        print "No usage data found."
        return
    }

    let block = ($result | first)

    print $"Current Block: ($block.block_id)"
    print $"Started: ($block.started)"
    print $"Messages: ($block.message_count)"
    print $"Cost: $($block.cost_usd)"

    if $block.is_active == "true" {
        print $"Status: ACTIVE \(($block.hours_left) hours remaining\)"
    } else {
        print "Status: EXPIRED"
    }
}

# Refresh pricing data
def "main refresh-pricing" [] {
    fetch-pricing --force
    print "Pricing data refreshed."
}

# Pacing / burndown help
def "main pace" [] {
    print "Pacing / burndown charts:"
    print "  claude-usage pace week   - Usage vs. the weekly limit (authoritative % from the statusline log)"
    print "  claude-usage pace week --proxy   - ccusage cost view of the last 7 days (works today)"
    print "  claude-usage pace month  - Cumulative cost this month vs. a pace line"
    print ""
    print "Options:"
    print "  --proxy         (week) cost-based view instead of the logged weekly-limit %"
    print "  --ceiling N     (week --proxy) reference ceiling USD (default: prior 7-day total)"
    print "  --budget N      (month) reference ceiling USD (default: previous month's total)"
    print "  --tokens        (month) chart total tokens instead of USD"
}

# Monthly pacing / burndown — cumulative API-equivalent cost this calendar month
# vs. a pace line. There is no monthly subscription cap, so this is $/token
# pacing: default reference is last month's total; --budget sets a hard ceiling.
def "main pace month" [
    --budget: float    # Reference ceiling in USD (default: previous month's total)
    --tokens           # Chart total tokens instead of USD cost
] {
    let ms = (month-start)
    let rows = (ccusage-daily (fmt-since $ms))
    if ($rows | is-empty) {
        print "No usage recorded yet this month."
        return
    }

    let metric = if $tokens { "totalTokens" } else { "totalCost" }
    let ylabel = if $tokens { "tokens" } else { "USD" }
    let unit = if $tokens { "" } else { "$" }

    # Cumulative actual, indexed by day-of-month.
    let daily = ($rows | each {|r| {
        day: ($r.period | into datetime | format date "%d" | into int)
        val: ($r | get $metric | into float)
    }})
    let cum = ($daily | reduce --fold { acc: 0.0, out: [] } {|it, st|
        let running = ($st.acc + $it.val)
        { acc: $running, out: ($st.out | append { day: $it.day, actual: $running }) }
    } | get out)

    let dim = (days-in-month)
    let elapsed = ($cum | last | get day)
    let so_far = ($cum | last | get actual)

    # Reference total: --budget, else last month's total, else trailing scale.
    let reference = if $budget != null {
        $budget
    } else {
        let lm = (last-month-total $tokens)
        if $lm > 0 { $lm } else { ($so_far / $elapsed) * $dim }
    }

    let chart = ($cum | each {|r| {
        day: $r.day
        actual: ($r.actual | math round --precision 2)
        pace: (($reference / $dim) * $r.day | math round --precision 2)
    }})

    let projected = (($so_far / $elapsed) * $dim)
    let status = if $projected > $reference { "OVER" } else { "under" }

    render-pace $chart $"Monthly pacing — ($ms | format date '%B %Y')" "day of month" $ylabel
    print $"  so far ($unit)($so_far | math round --precision 2)  ·  reference ($unit)($reference | math round --precision 2)  ·  projected month-end ($unit)($projected | math round --precision 2) [($status)]"
}

# ccusage cost proxy for the week — cumulative cost over the last 7 days vs. a
# ceiling. Works immediately over all history (unlike the logged %, which builds
# up over time).
def pace-week-proxy [ceiling?: float] {
    let rows = (ccusage-daily (fmt-since ((date now) - 7day)))
    if ($rows | is-empty) { print "No usage in the last 7 days."; return }
    let cum = ($rows | reduce --fold { acc: 0.0, out: [] } {|it, st|
        let running = ($st.acc + $it.totalCost)
        { acc: $running, out: ($st.out | append { actual: $running }) }
    } | get out)
    let total = ($cum | last | get actual)
    let reference = if $ceiling != null { $ceiling } else {
        let p = (prior-7day-total)
        if $p > 0 { $p } else { $total }
    }
    let chart = ($cum | enumerate | each {|e| {
        day: ($e.index + 1)
        actual: ($e.item.actual | math round --precision 2)
        pace: (($reference / 7.0) * ($e.index + 1) | math round --precision 2)
    }})
    render-pace $chart "Weekly pacing — ccusage cost proxy" "day of 7-day window" "USD"
    print $"  last 7 days $($total | math round --precision 2)  ·  reference ceiling $($reference | math round --precision 2)"
}

# Weekly pacing / burndown against the authoritative weekly usage limit. Reads
# the % logged by the statusline hook; falls back to the ccusage proxy on demand.
def "main pace week" [
    --proxy            # Use the ccusage cost proxy instead of the logged weekly-limit %
    --ceiling: float   # (with --proxy) reference ceiling USD (default: prior 7-day total)
] {
    if $proxy { pace-week-proxy $ceiling; return }

    let log_path = ($LIMITS_LOG | path expand)
    let samples = if ($log_path | path exists) {
        open $log_path | lines | where {|l| ($l | str trim | is-not-empty)} | each {|l| try { $l | from json } catch { null } } | compact
    } else { [] }
    let wk = ($samples | where {|r| (($r | get -o seven_day) | is-not-empty) } | sort-by ts)

    if ($wk | length) < 2 {
        print $"Weekly-limit history is still building — ($wk | length) sample\(s\) logged so far."
        print "The statusline records the real 7-day usage % as you work with Claude Code."
        print "For a view you can use right now:  ccu pace week --proxy"
        return
    }

    # Isolate the current weekly cycle (prefer resets_at; else cut at last reset).
    let latest_reset = ($wk | last | get -o resets_at)
    let cycle = if ($latest_reset | is-not-empty) {
        $wk | where {|r| ($r | get -o resets_at) == $latest_reset }
    } else {
        cut-at-last-reset $wk
    }

    # Pace line spans the 168h weekly window ending at reset.
    let reset_dt = if ($latest_reset | is-not-empty) {
        $latest_reset | into datetime
    } else {
        ($cycle | last | get ts | into datetime) + 1day
    }
    let window_start = ($reset_dt - 7day)

    let chart = ($cycle | each {|r|
        let elapsed_h = ((($r.ts | into datetime) - $window_start) / 1hr)
        {
            hours: ($elapsed_h | math round --precision 1)
            actual: ($r.seven_day | into float | math round --precision 1)
            pace: ((100.0 * $elapsed_h / 168.0) | math round --precision 1)
        }
    })
    render-pace $chart "Weekly usage vs. limit" "hours into 7-day window" "% of weekly limit"

    # Project current burn rate forward to the reset.
    let first = ($cycle | first)
    let last = ($cycle | last)
    let dt_h = ((($last.ts | into datetime) - ($first.ts | into datetime)) / 1hr)
    let cur = ($last.seven_day | into float)
    if $dt_h > 0 {
        let slope = (($cur - ($first.seven_day | into float)) / $dt_h)
        let projected = ($cur + $slope * ((($reset_dt) - ($last.ts | into datetime)) / 1hr))
        let verdict = if $projected >= 100 { "projected to hit the weekly limit before reset" } else { "on track to stay under" }
        print $"  now ($cur | math round --precision 1)%  ·  projected at reset ($projected | math round --precision 1)%  ·  ($verdict)"
        print $"  reset ($reset_dt | format date '%a %d %b %H:%M')"
    } else {
        print $"  now ($cur | math round --precision 1)% of weekly limit"
    }
}
