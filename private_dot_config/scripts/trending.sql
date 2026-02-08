-- Install and load the Full-Text Search (FTS) extension
INSTALL fts ;

LOAD fts ;

SET
scalar_subquery_error_on_multiple_rows = FALSE ;

SET VARIABLE trend_threshold = 10 ;

-- Create a function to normalize values using Min-Max scaling
CREATE OR REPLACE FUNCTION MINMAX (v) AS COALESCE ((v - MIN (v) OVER ()) / (MAX (v) OVER () - MIN (v) OVER ()),
0) ;

-- Create a function to clean URLs for better search results
CREATE OR REPLACE FUNCTION CLEAN_URL (url) AS REPLACE (
REGEXP_REPLACE (
REGEXP_REPLACE (
REGEXP_REPLACE (REGEXP_REPLACE (url, '^https?://', ''), '^www\.', ''),
'[^a-zA-Z0-9]',
' '
),
'\s+',
' '
),
' ',
' '
) ;

-- Create a table for casks data from JSON file
CREATE OR REPLACE TABLE casks AS
SELECT
*
FROM
READ_JSON ('/tmp/brew_trend/cask.json', format = 'array') ;

-- Create a table for core formula data from JSON file
CREATE OR REPLACE TABLE core AS
SELECT
*
FROM
READ_JSON ('/tmp/brew_trend/formula.json', format = 'array') ;

-- Create a corpus table combining casks and core data
CREATE OR REPLACE TABLE corpus AS
SELECT
'cask' AS category,
token AS name,
full_token AS full_name,
ARRAY_TO_STRING (name, ' ') AS aliases,
ARRAY_TO_STRING (old_tokens, ' ') AS old_names,
"desc" AS description,
homepage,
CLEAN_URL (homepage) AS homepage_clean
FROM
casks
UNION ALL
SELECT
'formula' AS category,
name,
full_name,
ARRAY_TO_STRING (aliases, ' ') AS aliases,
ARRAY_TO_STRING (oldnames, ' ') AS old_names,
"desc" AS description,
homepage,
CLEAN_URL (homepage) AS homepage_clean
FROM
core ;

-- Create a Full-Text Search (FTS) index on the corpus table
PRAGMA create_fts_index (
'corpus',
'name',
'name',
'full_name',
'aliases',
'old_names',
'description',
'homepage_clean'
) ;

-- Create a table for brew analytics data from multiple JSON files
CREATE OR REPLACE TABLE brew_analytics AS
SELECT
*
FROM
READ_JSON (
[
'/tmp/brew_trend/cask_30d.json',
'/tmp/brew_trend/cask_90d.json',
'/tmp/brew_trend/formula_30d.json',
'/tmp/brew_trend/formula_90d.json'
],
filename = TRUE,
columns = {
category: 'VARCHAR',
total_items: 'BIGINT',
start_date: 'DATE',
end_date: 'DATE',
total_count: 'BIGINT',
formulae: 'JSON'
}
) ;

-- Create a table for categorized items with their install counts
CREATE OR REPLACE TABLE categories AS
WITH
item_array AS (
SELECT
start_date,
end_date,
CASE
WHEN category = 'cask_install' THEN 'cask'
WHEN category = 'formula_install_on_request' THEN 'formula'
END AS category,
CONCAT ('d', REGEXP_EXTRACT (filename, '(\d+)d.json', 1)) AS days,
formulae ->> '$.*[*]' AS item_group
FROM
brew_analytics
),
items AS (
SELECT
category,
start_date,
end_date,
days,
UNNEST (item_group) AS item
FROM
item_array
)
SELECT
category,
start_date,
end_date,
days,
CASE
WHEN category = 'cask' THEN item ->> '$.cask'
WHEN category = 'formula' THEN item ->> '$.formula'
END AS name,
CAST (REPLACE (item ->> '$.count', ',', '') AS INTEGER) AS installs
FROM
items ;

-- Create a table for install counts pivoted by days
CREATE OR REPLACE TABLE installs AS
WITH
install_counts AS (
SELECT
category,
name,
days,
installs
FROM
categories
)
PIVOT install_counts ON days USING SUM (installs) ;

-- Create a table for measures including average installs and trend change
CREATE OR REPLACE TABLE measures AS
SELECT
*,
IFNULL (d30 / 30, 0) AS d30_avg,
IFNULL ((d90 - d30) / 60, 0) AS p60_avg,
CASE
WHEN d30_avg < getvariable ('trend_threshold') THEN 0
ELSE p60_avg / d30_avg
END AS trend_index
FROM
installs ;

-- Perform a search on the corpus using FTS and calculate distances for ranking
WITH
search AS (
SELECT
*,
fts_main_corpus.match_bm25 (name, getvariable ('search_term')) AS score
FROM
corpus
WHERE
score IS NOT NULL
),
results AS (
SELECT
*,
MINMAX (trend_index) AS trend_scaled,
MINMAX (d30) AS d30_scaled,
ARRAY_DISTANCE (CAST ([trend_scaled,
d30_scaled] AS FLOAT [2]),
CAST ([1,
1] AS FLOAT [2])) AS distance
FROM
search
LEFT JOIN measures ON search.name = measures.name
AND search.category = measures.category
)
SELECT
ROW_NUMBER () OVER (
ORDER BY
distance ASC
) AS rank,
category,
name,
d30 AS installs_30d,
trend_index,
description,
homepage
FROM
results ;
