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
    description: "Path to the CSV file",
    demandOption: true,
  })
  .help().argv;

const filePath = argv.file;

if (!filePath) {
  console.error("Please provide a file path as a parameter.");
  process.exit(1);
}

// Extract the file stem (file name without extension) and convert to snake case
const fileStem = toSnakeCase(path.basename(filePath, path.extname(filePath)));

// Create a DuckDB instance
const instance = await DuckDBInstance.create(":memory:");
const connection = await instance.connect();

const reader = await connection.runAndReadAll(
  `SELECT Prompt FROM sniff_csv('${filePath}');`,
);
const rows = reader.getRows();

// Extract the prompt string from the nested array
let promptString = rows[0][0];

// Replace tab, newline, and comma-space with escaped versions
promptString = promptString
  .replace(/\t/g, "\\t")
  .replace(/\n/g, "\\n")
  .replace(/, /g, ",\n\t");

const statement = `CREATE OR REPLACE TABLE ${fileStem} AS\nSELECT * ${promptString}`;

// Copy the prompt string to the clipboard
clipboardy.writeSync(statement);

console.log("Statement copied to clipboard.");
