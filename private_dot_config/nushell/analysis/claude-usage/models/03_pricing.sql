-- 03_pricing.sql
-- Create pricing dimension table from preprocessed pricing data
-- Pricing data is preprocessed by Nushell into a simple table format

CREATE OR REPLACE TABLE dim_pricing AS
SELECT * FROM read_csv($pricing_csv_path, header=true);
