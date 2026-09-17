# Fabric Metadata-Driven Ingestion — SQL Package

## 1) Run on Azure SQL Database — mock operational source

Run in this order:

1. `scripts/source/01_create_source_schema.sql`
2. `scripts/source/02_generate_source_data.sql`

Expected initial row counts:

- `crm.customers` = 5,000
- `partner.merchants` = 200
- `catalog.product_categories` = 20
- `catalog.products` = 4,000
- `sales.orders` = 20,000
- `sales.order_items` = 60,000

Do **not** run `03_simulate_incremental_changes.sql` until after the first successful REGULAR ingestion and the immediate no-new-data test. It is used later to create fresh rows/updates beyond the committed watermark.

## 2) Run on Fabric SQL Database — `sqldb_ecommerce_control`

Run in this order:

1. `scripts/control/01_create_control_schema.sql`
2. `scripts/control/02_create_control_procedures.sql`
3. `scripts/control/03_seed_ingestion_metadata.sql`

Expected metadata state after seeding:

- `control.ingestion_config` = 6 rows for `ECOMMERCE_AZSQL`
- `control.pipeline_watermarks` = 5 rows
- `catalog.product_categories` is FULL, so it has no watermark row
- All INCREMENTAL objects start at `1900-01-01T00:00:00.000`

## 3) Important design assumptions

- All timestamps are treated as UTC.
- Incremental extraction uses `LOW < updated_at <= HIGH`.
- `HIGH` must be captured before Copy Activity begins.
- `control.pipeline_watermarks` stores only current processing state, not history.
- `audit.ingestion_log` stores one terminal row per child pipeline execution.
- `pipeline_run_id` is unique because one Fabric child RunId maps to one terminal audit row.
- No custom ingestion-lock table is used in the core implementation.
- Normal operational execution must enter through `pl_master_ingestion`, configured with pipeline concurrency = 1.
- Optimistic watermark comparison remains the state-safety check during finalization.

## 4) Landing path convention

Incremental:

`<target_folder>/incremental/window=<LOW>_<HIGH>/`

Example:

`landing/sales/orders/incremental/window=20260915T010000000Z_20260915T020000000Z/`

Full:

`<target_folder>/full/current/`

Example:

`landing/catalog/product_categories/full/current/`

## 5) Incremental-change simulator

After the initial ingestion tests, run:

`scripts/source/03_simulate_incremental_changes.sql`

It performs:

- one new customer insert
- one existing customer update
- one existing product update
- one new order insert
- three new order-item inserts

All changes use the same fresh `SYSUTCDATETIME()` timestamp, making the next incremental window easy to validate.