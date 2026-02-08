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

    # Preprocess into CSV for DuckDB
    print "Processing pricing data..."
    let claude_models = [
        # Claude 4.5 models (current)
        "claude-sonnet-4-5-20250929"
        "claude-opus-4-5-20251101"
        "claude-haiku-4-5-20251001"
        # Claude 4 models
        "claude-sonnet-4-20250514"
        "claude-opus-4-20250514"
        # Claude 3.5 models
        "claude-3-5-sonnet-20241022"
        "claude-3-5-sonnet-20240620"
        "claude-3-5-haiku-20241022"
        # Claude 3 models
        "claude-3-opus-20240229"
        "claude-3-sonnet-20240229"
        "claude-3-haiku-20240307"
    ]

    let pricing_records = ($claude_models | each { |model|
        let data = ($pricing_json | get -o $model | default {})
        {
            model_name: $model
            input_cost_per_token: ($data | get -o input_cost_per_token | default 0)
            output_cost_per_token: ($data | get -o output_cost_per_token | default 0)
            cache_creation_cost_per_token: ($data | get -o cache_creation_input_token_cost | default 0)
            cache_read_cost_per_token: ($data | get -o cache_read_input_token_cost | default 0)
        }
    })

    $pricing_records | to csv | save -f $csv_path
    print "Pricing data cached."
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
}

# Query database and return CSV
def query-db [sql: string]: nothing -> string {
    let db_path = ($DB_PATH | path expand)
    $sql | duckdb -csv $db_path
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
    print ""
    print "Options:"
    print "  --days N    - Number of days (daily, default: 30)"
    print "  --weeks N   - Number of weeks (weekly, default: 12)"
    print "  --months N  - Number of months (monthly, default: 6)"
    print "  --limit N   - Number of sessions (sessions, default: 20)"
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
