#!/usr/bin/env zx

import { DuckDBInstance } from "@duckdb/node-api";
import clipboardy from "node-clipboardy";
import path from "path";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

// Parse command-line arguments using yargs
const argv = yargs(hideBin(process.argv))
  .option("file", {
    alias: "f",
    type: "string",
    description: "Path to the JSON file",
    demandOption: true,
  })
  .help().argv;

const filePath = argv.file;

if (!filePath) {
  console.error("Please provide a file path as a parameter.");
  process.exit(1);
}

// Extract the file stem (file name without extension)
const fileStem = path.basename(filePath, path.extname(filePath));

// Create a DuckDB instance
const instance = await DuckDBInstance.create(":memory:");
const connection = await instance.connect();

// Construct the DuckDB query to get the schema
const reader = await connection.runAndReadAll(
  `WITH      schema_list AS (
            SELECT    json_structure (value) AS schema
            FROM      read_csv ('${filePath}',
                      all_varchar = TRUE,
                      ignore_errors = TRUE,
                      columns={'value': 'VARCHAR'})
            )
  SELECT    schema
  FROM      schema_list
  GROUP BY  schema
  ORDER BY  LENGTH(schema) DESC
  LIMIT     1;`,
);

const rows = reader.getRows();

// Extract the prompt string from the nested array
let dataSchema = rows[0][0];

dataSchema = dataSchema.replace(/,/g, ",\n\t");

// Construct the final SQL statement
const statement = `
  SET VARIABLE data_schema = '${dataSchema}';

  CREATE OR REPLACE TABLE ${fileStem} AS
  WITH source_data AS (
    SELECT UNNEST(string_split_regex(content, '\\n')) AS json_value
    FROM read_text('${filePath}')
  ),
  records AS (
    SELECT json_transform(json_value, getvariable('data_schema')) AS record
    FROM source_data
  )
  SELECT record.*
  FROM records;
`;

// Copy the statement to the clipboard
clipboardy.writeSync(statement.trim());

console.log("Statement copied to clipboard.");
