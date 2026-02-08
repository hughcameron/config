-- UNPIVOT (
--     SELECT
--         'community' AS repository,
--         *
--     FROM
--         'https://community-extensions.duckdb.org/downloads-last-week.json'
-- ) ON COLUMNS (* EXCLUDE (_last_update, repository)) INTO NAME extension VALUE downloads_last_week
-- ORDER BY
--     downloads_last_week DESC;


PIVOT (
    UNPIVOT (
        FROM read_json([
            printf('https://community-extensions.duckdb.org/download-stats-weekly/%s.json',
                strftime(x, '%Y/%W')
            )
            FOR x
            IN range(TIMESTAMP '2024-10-01', now()::TIMESTAMP, INTERVAL 1 WEEK)
            IF strftime(x, '%W') != '53'
        ])
    )
    ON COLUMNS(* EXCLUDE _last_update)
    INTO NAME extension VALUE downloads
)
ON date_trunc('day', _last_update)
USING any_value(downloads)
ORDER BY extension;
