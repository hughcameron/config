# Nushell script to analyze Homebrew trends
#
# This script fetches Homebrew package analytics, calculates trends using DuckDB,
# and displays the results in VisiData.

# --- Configuration ---
$env.BREWTREND_DIR = "/Users/hugh/.config/nushell/analysis/brewtrend"
$env.DATA_DIR = $"($env.BREWTREND_DIR)/data"
$env.MODELS_DIR = $"($env.BREWTREND_DIR)/models"
$env.DB_PATH = $"($env.DATA_DIR)/trends.db"

# A table of data files to fetch, with URLs and local paths
let BREW_DATA_FILES = [
    { name: "cask"          url: "https://formulae.brew.sh/api/cask.json"                                  path: $"($env.DATA_DIR)/cask/cask.json" }
    { name: "formula"       url: "https://formulae.brew.sh/api/formula.json"                               path: $"($env.DATA_DIR)/formula/formula.json" }
    { name: "cask_30d"      url: "https://formulae.brew.sh/api/analytics/cask-install/homebrew-cask/30d.json"   path: $"($env.DATA_DIR)/cask/30d.json" }
    { name: "cask_90d"      url: "https://formulae.brew.sh/api/analytics/cask-install/homebrew-cask/90d.json"   path: $"($env.DATA_DIR)/cask/90d.json" }
    { name: "formula_30d"   url: "https://formulae.brew.sh/api/analytics/install-on-request/homebrew-core/30d.json" path: $"($env.DATA_DIR)/formula/30d.json" }
    { name: "formula_90d"   url: "https://formulae.brew.sh/api/analytics/install-on-request/homebrew-core/90d.json" path: $"($env.DATA_DIR)/formula/90d.json" }
]

# --- Data Fetching ---

# Fetches Homebrew analytics data, using a cache to avoid redundant downloads.
def fetch-data [--force] {
    print "Fetching Homebrew analytics data..."
    mkdir $env.DATA_DIR
    
    for file in $BREW_DATA_FILES {
        let needs_refresh = if not ($file.path | path exists) {
            true
        } else {
            let modified = (ls $file.path | get modified.0)
            let expires = $modified + 24hr
            $expires < (date now)
        }

        if $force or $needs_refresh {
            print $"  - Downloading ($file.name)..."
            mkdir ($file.path | path dirname)
            http get --raw $file.url | save -f $file.path
        } else {
            print $"  - Using cached ($file.name)"
        }
    }
    print "✓ Data fetch complete."
}

# --- Database ---

    # Executes a SQL file using DuckDB
def run-sql [sql_file: string] {
    let sql_path = ($env.MODELS_DIR | path join $sql_file)
    print $"Executing SQL: ($sql_file)..."
    # Execute duckdb from BREWTREND_DIR to resolve relative paths in SQL files
    do {
        cd $env.BREWTREND_DIR
        duckdb -bail $env.DB_PATH -f $sql_path
    }
}
# Loads the downloaded JSON data into the database
def load-data [] {
    print "📊 Loading data into DuckDB..."
    run-sql "load_data.sql"
}

# Calculates trend metrics
def calculate-trends [] {
    print "📈 Calculating trends..."
    run-sql "trending.sql"
}

# --- Main Command ---

# Search trending Homebrew packages
export def main [
    search_term?: string, # Optional search term to filter packages
    --force_fetch(-f) # Force a refresh of the cached data
    --help(-h) # Show help message
] {
    if $help {
        help main
        return
    }

    fetch-data --force=$force_fetch
    
    # Reset and process data
    rm -f $env.DB_PATH
    load-data
    calculate-trends

    if not ($search_term | is-empty) {
        # --- Search Mode ---
        print $"🔍 Searching for '($search_term)' and launching VisiData..."
        with-env { SEARCH_TERM: $search_term } {
            run-sql "search_trending.sql"
        }
        duckdb $env.DB_PATH -json -c "SELECT * FROM search_results ORDER BY rank ASC" | vd -f json
    } else {
        # --- Interactive Ranking Mode ---
        print "🏆 Generating full ranking and launching VisiData..."
        run-sql "full_ranking.sql"
        duckdb $env.DB_PATH -json -c "SELECT * FROM ranking ORDER BY rank ASC LIMIT 100" | vd -f json
    }

    # --- Post-VisiData Actions ---
    print "" # newline
    let selected_package_name = (input "Enter package name to act on (or press Enter to exit): ")

    if ($selected_package_name | is-empty) {
        print "Exiting."
        return
    }

    # Get details for the selected package
    let pkg_result = (duckdb $env.DB_PATH -json -c $"SELECT * FROM all_packages WHERE name = '($selected_package_name)' LIMIT 1" | from json)

    if ($pkg_result | is-empty) {
        print $"Package '($selected_package_name)' not found."
        return
    }

    let pkg = ($pkg_result | get 0)

    let install_cmd = if $pkg.category == "cask" {
        $"brew install --cask ($pkg.name)"
    } else {
        $"brew install ($pkg.name)"
    }

    # Action menu
    let action = (input $"
Actions for ($pkg.name)
1: Install package ($install_cmd)
2: Open homepage ($pkg.homepage)
3: Copy install command to clipboard
Choose an action [1-3]: ")

    match $action {
        "1" => {
            print $"Running: ($install_cmd)"
            nu -c $install_cmd
        }
        "2" => {
            if not ($pkg.homepage | is-empty) {
                print $"Opening: ($pkg.homepage)"
                open $pkg.homepage
            } else {
                print "No homepage available."
            }
        }
        "3" => {
            print "Install command copied to clipboard."
            $install_cmd | cb
        }
        _ => {
            print "Invalid selection. Exiting."
        }
    }
}
