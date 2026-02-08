#!/usr/bin/env zx

import { DuckDBInstance } from "@duckdb/node-api";
import clipboardy from "node-clipboardy";
import path from "path";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

// Function to convert a string to snake case
function toSnakeCase(str) {
  return str
    .replace(/([a-z])([A-Z])/g, "$1_$2") // Add underscore between camelCase words
    .replace(/\s+/g, "_") // Replace spaces with underscores
    .replace(/-/g, "_") // Replace hyphens with underscores
    .toLowerCase(); // Convert to lowercase
}

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

// Extract the file stem (file name without extension) and convert to snake case
const ext = path.extname(filePath);
const fileStem = toSnakeCase(path.basename(filePath, ext));

const jsonFormat = [".ndjson", ".jsonl"].includes(ext)
  ? "newline_delimited"
  : "auto";

// Create a DuckDB instance
const instance = await DuckDBInstance.create(":memory:");
const connection = await instance.connect();

// Construct the DuckDB query to get the schema
const reader = await connection.runAndReadAll(
  `CREATE
  OR        REPLACE TABLE ${fileStem} AS
            SELECT    *
            FROM      read_json_objects ('${filePath}', FORMAT = '${jsonFormat}');

  SELECT    TO_JSON(map (list (column_name), list (data_type))) AS schema
  FROM      information_schema.columns
  WHERE     table_name = '${fileStem}'
  GROUP BY  table_name;`,
);

const rows = reader.getRows();

// Log the rows to debug the issue
console.log("Rows:", rows);

if (rows.length === 0) {
  console.error("No rows returned from the schema query.");
  process.exit(1);
}

// Extract the prompt string from the nested array
let dataSchema = rows[0][0];

dataSchema = dataSchema.replace(/,/g, ",\n\t");

// Construct the final SQL statement
const statement = `
  SET VARIABLE data_schema = '${dataSchema}';

  CREATE OR REPLACE TABLE ${fileStem} AS
  SELECT * FROM read_json('${filePath}',
  columns = getvariable('data_schema'),
  format = 'unstructured');
`;

// Copy the statement to the clipboard
clipboardy.writeSync(statement.trim());

console.log("Statement copied to clipboard.");
