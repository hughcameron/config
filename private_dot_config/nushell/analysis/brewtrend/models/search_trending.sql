-- Install and load the Full-Text Search (FTS) extension
INSTALL fts;
LOAD fts;

SET scalar_subquery_error_on_multiple_rows=false;

-- Create a function to clean URLs for better search results
CREATE OR REPLACE FUNCTION CLEAN_URL(url) AS
    REPLACE(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(url, '^https?://', ''),
                    '^www\.', ''
                ),
                '[^a-zA-Z0-9]', ' '
            ),
            '\s+', ' '
        ),
        ' ', ' '
    );

-- Create a corpus table combining casks and core data
CREATE OR REPLACE TABLE corpus AS
SELECT
    'cask' AS category,
    token AS name,
    full_token AS full_name,
    array_to_string(name, ' ') AS aliases,
    array_to_string(old_tokens, ' ') AS old_names,
    "desc" AS description,
    homepage,
    CLEAN_URL(homepage) as homepage_clean
FROM casks
UNION ALL
SELECT
    'formula' AS category,
    name,
    full_name,
    array_to_string(aliases, ' ') AS aliases,
    array_to_string(oldnames, ' ') AS old_names,
    "desc" AS description,
    homepage,
    CLEAN_URL(homepage) as homepage_clean
FROM core;

-- Create a Full-Text Search (FTS) index on the corpus table
PRAGMA create_fts_index(
    'corpus',
    'name',
    'name',
    'full_name',
    'aliases',
    'old_names',
    'description',
    'homepage_clean',
    overwrite=true
);

-- Perform a search on the corpus using FTS and calculate distances for ranking
CREATE OR REPLACE TABLE search_results AS
WITH search AS (
    SELECT
        *,
        fts_main_corpus.match_bm25(name, getenv('SEARCH_TERM')) AS score
    FROM corpus
    WHERE score IS NOT NULL
),
results AS (
    SELECT
        *,
        MINMAX(trend_index) AS trend_scaled,
        MINMAX(d30) AS d30_scaled,
        array_distance(
            CAST([trend_scaled, d30_scaled] AS FLOAT[2]),
            CAST([1, 1] AS FLOAT[2])
        ) AS distance
    FROM search
    LEFT JOIN measures ON search.name = measures.name AND search.category = measures.category
)
SELECT
    ROW_NUMBER() OVER (ORDER BY distance ASC) AS rank,
    category,
    name,
    CAST(d30 AS INTEGER) AS installs_30d,
    trend_index,
    description,
    homepage
FROM results;

COPY search_results TO 'data/ranking.parquet';
