
# alt-shift-b chord

## b: Run in BigQuery
```sh
cat {file} | bq query --quiet --nouse_legacy_sql
```

## v: BigQuery to Visidata
```sh
cat {file} | bq query --quiet --format=json --nouse_legacy_sql | vd -f json
```

## j: BigQuery to JLESS
```sh
cat {file} | bq query --quiet --format=json --nouse_legacy_sql | jless
```


# alt-shift-d chord

## d: Run in DuckDB
```sh
duckdb -f {file}
```

## v: DuckDB to Visidata
```sh
duckdb -json -f {file} | vd -f json
```

## j: DuckDB to JLESS
```sh
duckdb -json -f {file} | jless
```

# alt-shift-g chord

## b: Browse Repository in GitHub
```sh
gh browse .
```
