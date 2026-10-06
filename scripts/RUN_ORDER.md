# Fabric Metadata-Driven Ingestion — SQL Package

## 1) Run on Azure SQL Database — `sql_ecommerce_db`

Run in this order:

1. `scripts/source/01_create_source_schema.sql`
2. `scripts/source/02_generate_source_data.sql`
3. `scripts/security/01_grant_fabric_basic_source_read.sql`

Before running the security script:

- Replace `REPLACE_WITH_STRONG_PASSWORD` with a strong password before execution.
- Do not commit the real password to Git.
- The script creates the contained database user `fabric_ingestion_user`.
- The user receives read-only access to the `crm`, `partner`, `catalog`, and `sales` schemas.

Expected initial row counts:

- `crm.customers` = 5,000
- `partner.merchants` = 200
- `catalog.product_categories` = 20
- `catalog.products` = 4,000
- `sales.orders` = 20,000
- `sales.order_items` = 60,000

Do **not** run `03_simulate_incremental_changes.sql` until after the first
successful REGULAR ingestion and the immediate no-new-data test.

It is used later to create fresh rows and updates beyond the committed watermark.

## 2) Run on Fabric SQL Database — `sqldb_ingestion_control`

Run in this order:

1. `scripts/control/01_create_control_schema.sql`
2. `scripts/control/02_create_control_procedures.sql`
3. `scripts/control/03_seed_connection_settings.sql`
4. `scripts/control/04_seed_ingestion_metadata.sql`

`02_create_control_procedures.sql` is idempotent and contains both ingestion finalization and top-level explicit-request validation procedures. Rerun it after pulling framework changes that modify either control procedure.

Expected metadata state after seeding:

- `control.ingestion_config` = 8 rows total: 6 `ECOMMERCE` DATABASE configs + 2 `LOGISTICS_VENDOR` FILE configs
- 6 DATABASE configs remain active
- FILE/FULL `LOGISTICS_VENDOR.inventory_snapshot` is active
- FILE/INCREMENTAL `LOGISTICS_VENDOR.inventory_movement` is active after the incremental route is synced
- Current DATABASE configs use `source_path = NULL`, `source_options = NULL`, and `landing_path = NULL`
- `copy_options` is NULL by default; `sales.order_items` demonstrates `DYNAMIC_RANGE` on `order_item_id` with service-managed copy parallelism
- `control.pipeline_watermarks` = 6 rows: 5 DATABASE incremental + 1 FILE incremental
- `catalog.product_categories` is FULL, so it has no watermark row
- DATABASE incremental objects start at `1900-01-01T00:00:00.000`
- FILE incremental uses the same `control.pipeline_watermarks` table with `watermark_field = last_modified_time` and initial checkpoint `1900-01-01T00:00:00.000Z`

## 3) Source authentication

The current project uses Basic authentication for the Azure SQL source connection:

- Azure SQL connection: `cn_azsql_ecommerce`
- Database user: `fabric_ingestion_user`
- Access: read-only source schemas
- SFTP connection: `cn_sftp_logistics_vendor`
- SFTP consumer user: `fabric_sftp_user`
- SFTP producer/demo user: `vendor_sftp_user`

Basic authentication is used because the Fabric workspace and Azure SQL source
are hosted in different Microsoft Entra tenants.

The preferred production pattern is Fabric Workspace Identity when both services
are hosted in the same Microsoft Entra tenant.

## 4) Important design assumptions

- All timestamps are treated as UTC.
- Incremental extraction uses `LOW < updated_at <= HIGH`.
- `HIGH` must be captured before Copy Activity begins.
- `control.pipeline_watermarks` stores only current processing state, not history.
- `audit.ingestion_log` stores one terminal row per child pipeline execution.
- `pipeline_run_id` is unique because one Fabric child RunId maps to one terminal audit row.
- No custom ingestion-lock table is used in the core implementation.
- Normal operational execution must enter through `pl_ingest_orchestrator`, configured with pipeline concurrency = 1.
- Optimistic watermark comparison remains the state-safety check during finalization.

Top-level execution uses `pl_ingest_orchestrator.p_run_requests`:

- `[]` runs all active configurations as REGULAR with pagination.
- A non-empty array runs exactly the requested configs; each object carries
  `config_id`, `run_type`, `lower_bound`, and `upper_bound`.
- REGULAR leaves LOW/HIGH empty.
- `load_strategy` remains the config's FULL/INCREMENTAL strategy for every run. BACKFILL + FULL uses empty LOW/HIGH and rereads the full current source scope; BACKFILL + INCREMENTAL requires explicit LOW/HIGH and never advances the operational watermark.
- See `docs/operations/run-request-examples.md` for copy/paste examples.

## 5) Current relational Bronze target convention

The current DATABASE ingestion path writes relational sources directly to Bronze
Lakehouse Delta tables. For these configs, `source_path` and `landing_path` are
NULL; the source is resolved through `source_schema` + `source_object`, while
the Bronze target is resolved through `target_conn_ref`, `target_schema`, and
`target_table`.

FILE ingestion uses the same `control.ingestion_config` table:

- `source_path` identifies where the source data is located.
- `landing_path` identifies the platform-owned Landing Zone path.
- `file_format` selects the Landing-to-Bronze parser for FILE ingestion.
- `source_options` stores format/source-specific options. The current `DELIMITED_TEXT` contract requires file-name pattern, delimiter, header, encoding, quote, and escape.

No separate `file_ingestion_config` table or Quarantine area is used in the
current project scope.

For an existing live control database created before M76, run
`scripts/control/migrations/001_refine_ingestion_metadata.sql` instead of rerunning
the destructive bootstrap schema script.

For a live control database created before database copy tuning metadata was added, also run:

`scripts/control/migrations/006_add_copy_options.sql`

To remove the retired framework-level `RERUN` run type from an existing control database, also run:

`scripts/control/migrations/007_remove_rerun_run_type.sql`

The migration refuses to rewrite historical `RERUN` audit rows automatically. If any exist, review them explicitly before applying the tighter constraint.

Then rerun `scripts/control/04_seed_ingestion_metadata.sql` after the Fabric pipeline artifacts are synced.

After creating Fabric connection `cn_sftp_logistics_vendor`, run
`scripts/control/migrations/002_add_sftp_connection.sql` with its Connection ID. For an existing control database, also run `scripts/control/migrations/004_add_file_format.sql`, then rerun `scripts/control/04_seed_ingestion_metadata.sql` to register/refresh FILE metadata. Sync the pipeline artifacts from Git before rerunning the seed because the FILE config is active.

## 6) Incremental-change simulator

After the initial ingestion tests, run:

`scripts/source/03_simulate_incremental_changes.sql`

It performs:

- one new customer insert
- one existing customer update
- one existing product update
- one new order insert
- three new order-item inserts

All changes use the same fresh `SYSUTCDATETIME()` timestamp, making the next incremental window easy to validate.

## 7) FILE FULL implementation

The first FILE route is:

```text
pl_ingest_object_controller
  -> FILE|LAKEHOUSE|FULL
  -> pl_ingest_file_full_router
  -> SFTP
  -> pl_ingest_sftp_full_adapter
```

The SFTP child first performs a Binary copy to Lakehouse Files Landing, preserving the raw file. It then invokes `nb_load_file_landing_to_bronze`, which dispatches the parser by `file_format`. The currently implemented `DELIMITED_TEXT` reader appends to the Bronze Delta table with the standard technical columns `_batch_id`, `_pipeline_run_id`, `_ingestion_timestamp`, `_source_file_name`, and `_source_file_path`.

The current FULL feed uses the stable producer filename
`inventory_snapshot.csv`. Each run writes Landing to a batch-specific path:

```text
Files/landing/logistics_vendor/inventory_snapshot/ingestion_date=YYYY-MM-DD/batch_id=<batch_id>/
```

This prevents one FULL run from re-reading a directory of historical dated
snapshots and preserves each raw delivery independently.


## 8) FILE incremental implementation

For an existing live control database, run:

```text
scripts/control/migrations/003_generalize_pipeline_watermark.sql
scripts/control/migrations/004_add_file_format.sql
scripts/control/02_create_control_procedures.sql
scripts/control/04_seed_ingestion_metadata.sql
```

The migration changes `control.pipeline_watermarks.last_watermark_value` from
DATETIME2 to STRING while preserving existing DATABASE watermark values in
ISO-8601 format. It also changes audit `processing_lower_bound` and
`processing_upper_bound` to STRING. The same two boundary fields are used by
DATABASE, FILE, and future API adapters; there is no second
`watermark_lower_value` / `watermark_upper_value` pair.

The first FILE incremental route is:

```text
pl_ingest_object_controller
  -> FILE|LAKEHOUSE|INCREMENTAL
  -> pl_ingest_file_incremental_router
  -> SFTP
  -> pl_ingest_sftp_incremental_adapter
  -> recursive Binary copy to Landing
  -> nb_load_file_landing_to_bronze
```

The incremental feed is:

```text
source_object      = inventory_movement
source_path        = /outbound/inventory/movements/
file_format        = DELIMITED_TEXT
file_name_pattern  = inventory_movement_*.csv
landing_path       = Files/landing/logistics_vendor/inventory_movement/
target_table       = fulfillment.inventory_movements
load_strategy      = INCREMENTAL
watermark_field    = last_modified_time
```

The FILE format is first-class parsing metadata. Source-to-Landing remains Binary/raw, then `nb_load_file_landing_to_bronze` selects the format-specific reader. The currently implemented reader is `DELIMITED_TEXT`; unsupported formats fail explicitly until a reader is implemented.

The file config keeps `load_strategy = INCREMENTAL` for both REGULAR and BACKFILL runs. REGULAR uses the native Last Modified window `[current watermark, run start time)` and advances the checkpoint after successful finalization. BACKFILL uses explicitly requested LOW/HIGH Last Modified boundaries and never advances the operational checkpoint. Both execution paths preserve source-relative hierarchy under the batch Landing root before the generic notebook parses that batch.

Acceptance fixtures:

```text
sample-data/sftp/outbound/inventory/movements/
  inventory_movement_20260927T081500Z.csv
  inventory_movement_20260927T131500Z.csv
```

Recommended acceptance sequence:

1. Upload only `inventory_movement_20260927T081500Z.csv`.
2. Run the FILE incremental config: expect 6 Bronze rows and a
   `last_watermark_value` equal to that run's captured upper time.
3. Run again with no new file: expect `SUCCESS` with zero rows, no new Bronze rows, and the
   checkpoint to advance to the second scan's upper time.
4. Upload `inventory_movement_20260927T131500Z.csv`.
5. Run again: expect 6 additional Bronze rows and another forward movement of
   `last_watermark_value`.

The actual watermark is a UTC timestamp from the ingestion run, not a filename.

## 9) One-time FILE Bronze timestamp migration

If the FILE Bronze tables were created before the loader normalized
`_ingestion_timestamp` to Spark `TIMESTAMP`, run:

```text
scripts/lakehouse/migrations/001_normalize_file_ingestion_timestamp.sql
```

Run it in a Fabric Notebook SQL cell (Spark SQL) with `lh_ecommerce_bronze`
attached as the default Lakehouse. Do not run it against the Lakehouse SQL
analytics endpoint.

The migration rewrites the two current FILE Bronze tables with
`_ingestion_timestamp` cast to `TIMESTAMP` and is safe to rerun. After it
completes, rerun the failed FILE ingestion request.

## 10) Optional permanent Azure SQL performance benchmark

The scale benchmark is intentionally isolated from `sql_ecommerce_db`.

Create a separate free Azure SQL database:

```text
sql_ingestion_benchmark
```

Then follow `scripts/benchmark/README.md`.

One-time source setup:

```text
scripts/benchmark/01_create_benchmark_source.sql
scripts/benchmark/02_generate_benchmark_data.sql
scripts/benchmark/03_grant_fabric_benchmark_read.sql
```

The default fixture keeps both source shapes permanently:

```text
benchmark.copy_source_unpartitioned = 10,000,000 rows
benchmark.copy_source_partitioned   = 10,000,000 rows
```

Create Fabric connection `cn_azsql_ingestion_benchmark`, then register it and
the inactive benchmark configs:

```text
scripts/benchmark/04_register_benchmark_connection.sql
scripts/benchmark/05_register_benchmark_configs.sql
```

Use `06_set_benchmark_scenario.sql` only when benchmarking. The benchmark
configs stay inactive by default so normal master execution never copies the
large fixtures accidentally.

Current FULL Azure SQL benchmark strategies:

```text
NONE
DYNAMIC_RANGE
PHYSICAL_PARTITIONS
```

The current INCREMENTAL Azure SQL adapter supports `NONE` and
`DYNAMIC_RANGE`; physical partitions are intentionally exercised as a FULL
source-table strategy.

