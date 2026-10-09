# Fabric Metadata-Driven Ingestion — Starter Kit Run Order

This is the **current-baseline fresh-install** guide for the Personal
Fabric ingestion framework. It is NOT a historical upgrade checklist.
Core Control/Audit SQL is the same across DEV, UAT and PROD; source demo and
benchmark fixtures are optional and DEV-only.

## A. Prerequisites / Fabric items

- Fabric workspace with `sqldb_ingestion_control`, Bronze Lakehouse, the
  framework Data Pipelines and the three Notebook items from `fabric/`.
- Sync `fabric/vl_ingestion_connections.VariableLibrary` into the same
  workspace as `pl_ingest_orchestrator`.
- Set four environment-specific **String** values in the active Library:
  `control_db_connection_id`, `control_db_item_id`,
  `pipeline_invoke_connection_id`, `notebook_execution_connection_id`.
  Committed Library defaults are deliberately blank.
- Grant access to each Fabric Connection, SQL Database, Notebook, Lakehouse
  and child Pipeline as appropriate. Verify Invoke and Notebook targets
  are correctly rebound after workspace deployment.
- Source and target Copy Connections come from SQL
  `control.connection_settings`, NOT the four runtime variables.
  See [Variable Library configuration](../docs/operations/variable-library-environment-binding.md).

## B. Core Control Plane — mandatory SQL

Run in `sqldb_ingestion_control`, in order:

```text
scripts/control/01_create_control_schema.sql
scripts/control/02_create_control_procedures.sql
scripts/control/99_verify_control_plane.sql
```

This installs four tables, three Audit indexes, the Watermark view and
two procedures. Bootstrap `01` is **non-destructive** (CREATE-IF-ABSENT;
no DROP TABLE/VIEW); `02` uses CREATE OR ALTER. `99` checks the
current schema's keys, trusted constraints, view, procedures and indexes.
The SQL Database Project in `fabric/sqldb_ingestion_control.SQLDatabase/`
is the physical schema source of truth.

**Important:** CREATE-IF-ABSENT does not migrate an old populated database.
Only run these steps on an empty/new SQL Database or one already verified
to match this Baseline. Never run demo seeds against UAT/PROD by default.
The confirmed DEV migration history was removed from `main` during Starter
Kit cleanup; it remains accessible through
[Git history at the pre-cleanup revision](https://github.com/getnkit/fabric-metadata-driven-ingestion/tree/bf04ff6e67ed365c58adb8c07b94e1256b005bd1/scripts/control/migrations).
Legacy environments require a reviewed upgrade, not the Fresh-Install script.

## C. Optional DEV demo source

On the same RDS for SQL Server instance, connect as the RDS database administrator and run `CREATE DATABASE [sql_ecommerce_db];` once. Select that database in the SQL client. Then prepare the demo source:

```text
scripts/source/01_create_source_schema.sql
scripts/source/02_generate_source_data.sql
scripts/security/01_grant_fabric_basic_source_read.sql
```

The RDS security script creates a server-level SQL LOGIN in `master`, maps a database USER in `sql_ecommerce_db` and grants least-privilege read access. Replace the password placeholder locally, never commit it. Run the script with an RDS administrator permitted to create logins. Expected initial demo row counts:

| Source | Rows |
| --- | ---: |
| crm.customers | 5,000 |
| partner.merchants | 200 |
| catalog.product_categories | 20 |
| catalog.products | 4,000 |
| sales.orders | 20,000 |
| sales.order_items | 60,000 |

For FILE testing, provision the SFTP connection and put the sample files
from `sample-data/sftp/outbound/inventory/` onto the demo SFTP server.
Check remote paths, credentials and permissions.

## D. Optional DEV demo Control metadata

Set the **five connection/item/workspace IDs** at the start of
`scripts/control/03_seed_connection_settings.sql` to real DEV values.
The script does not contain committed environment GUIDs.

Then run:

```text
scripts/control/03_seed_connection_settings.sql
scripts/control/04_seed_ingestion_metadata.sql
scripts/control/99_verify_control_plane.sql
```

The connection seed creates logical `RDS_ECOMMERCE`,
`SFTP_LOGISTICS_VENDOR` and `LH_ECOMMERCE_BRONZE` references;
the ingestion metadata seed registers **six DATABASE + two FILE**
sample configs. It creates initial Watermark State only for missing
DATABASE/FILE INCREMENTAL config IDs (five DATABASE and one FILE).
FULL configs have no watermark row.

**Seed safety:** `04_seed_ingestion_metadata.sql` can UPDATE existing
sample configs; review before rerun. It **does not UPDATE existing
checkpoint rows**, change stored Watermark Fields, reset successes, or
rewrite Audit History. Mismatched metadata vs Watermark State must fail
during adapter validation and be reconciled explicitly, never reset by
an ad hoc seed. There are no default API incremental state rows.

## E. Execute via Master and verify

Create a Fabric **Amazon RDS for SQL Server** connection (`cn_src_rds_sql_server`) with Basic authentication, RDS endpoint/port 1433, and database `sql_ecommerce_db`. Use the read-only login from the security script; test connectivity and TLS/network restrictions. Populate `@SourceConnectionId` in seed `03` using **this** connector's ID. The RDS database is bound in Fabric Connection; metadata JSON contains its `connectionId` only. Source SQL Server is separate from the Fabric Control SQL Database.

Run only `pl_ingest_orchestrator` as the standard entry point:
`p_run_requests = []` runs all active configs as REGULAR; a non-empty
array runs explicit `config_id` and `run_type` requests. Backfill is
an explicit request with LOW/HIGH for INCREMENTAL. Supported run types
are REGULAR and BACKFILL; `load_strategy` remains FULL/INCREMENTAL.

- DATABASE: Amazon RDS for SQL Server reads directly into Bronze Delta; source-derived
  HIGH comes from the configured watermark column; REGULAR with
  HIGH=LOW is `SKIPPED` without Watermark advancement.
- FILE: SFTP Binary Copy persists the source file into Lakehouse Files
  Landing first; `landing_path` in metadata is **Files-relative**
  (`landing/...`, NOT `Files/landing/...`). The File Router validates
  `DELIMITED_TEXT` support before invoking FULL/INCREMENTAL adapters.
  FILE INCREMENTAL uses `last_modified_time`; no matched files
  results in `SKIPPED` without advancement.
- Every successful nonempty ingestion appends an immutable Bronze batch.
  Failed Bronze/Copy operations use existing compensation logic.
  BACKFILL never advances the operational Watermark State.
- Verify SQL audit exactly once per object child RunId, status and
  source/target counts, processing LOW/HIGH, correct advancement and
  optimistic conflict protection. UTC timestamps are standard.
- For File regression, test `inventory_snapshot.csv` and the sample
  `inventory_movement_*.csv` files; verify full and incremental runs,
  an empty incremental run, and explicit BACKFILL.
- **Runtime acceptance required:** SQL Lookup/Stored Procedure,
  Invoke Pipeline, dynamic Notebook execution Connection, Copy,
  Landing, Bronze and all failure paths must pass in Fabric DEV.
  Git static validation alone does not establish runtime compatibility.

More details:
[run requests](../docs/operations/run-request-examples.md),
[FILE design](../docs/architecture/file-ingestion-design.md),
[watermark semantics](../docs/architecture/generic-incremental-watermark.md),
[retry/rerun/backfill](../docs/operations/retry-rerun-backfill.md),
[SQL verification](../docs/operations/sql-control-plane-hardening.md).

## F. Optional performance benchmark (separate)

The independent 1M-row performance fixtures and scenario scripts remain in
`scripts/benchmark/` with their own [README](benchmark/README.md).
Run them in a **separate database on the same RDS instance** (not another instance), or a separate instance only when benchmarking warrants its cost. Default is 1M rows per table to stay comfortably below SQL Server Express's 10-GB-per-database limit. Benchmark configs
are inactive by default and **not part of the starter installation**.

## Release note

The SQL Database Project may include Fabric-exported, workspace-specific
security principals and schema owners. **Do not blindly deploy these
identities across environments**; review SQL Project security and
permissions during provisioning. This cleanup intentionally leaves those
security artifacts untouched to avoid unintended ownership or DROP USER
changes in the existing DEV database.

## G. RDS connection cutover notes

- New route: `AMAZON_RDS_SQL_SERVER|FULL` and `AMAZON_RDS_SQL_SERVER|INCREMENTAL`.
- New source ref: `RDS_ECOMMERCE`; keep `source_system = ECOMMERCE` and all existing target schemas.
- Rename the three pipeline items via Fabric Git sync; their existing `.platform` logicalIds are retained. Confirm parent/child Invoke targets resolve after sync.
- **Existing DEV metadata**: after RDS Fabric Connection is created and tested, set `@RdsConnectionId` and execute [`scripts/operations/01_cutover_existing_dev_to_rds.sql`](operations/01_cutover_existing_dev_to_rds.sql) in the **Fabric Control SQL Database**, NOT RDS. This transaction adds `RDS_ECOMMERCE`, rebinds only ECOMMERCE config rows without changing their IDs, removes the unreferenced legacy `AZSQL_ECOMMERCE` connection, and enforces the new CHECK. It does **not** reset `control.pipeline_watermarks` or modify audit rows. If other Azure SQL refs remain, it fails closed. Then execute `scripts/control/99_verify_control_plane.sql`. For a fresh empty Fabric Control Database, simply run the normal seeds `03 -> 04` and do **not** run the cutover script.
- The RDS Connector Dataset takes its database from Fabric Connection, rather than from Azure SQL's `datasetSettings.typeProperties.database`. Verify Source Lookup and Copy in Fabric before treating the migration as accepted.
- A switch to a different physical source does **not** guarantee Watermark continuity. Check existing LOW against the migrated RDS source's `MAX(updated_at)` and data history; if a deliberate rebaseline is necessary, do it as a separate reviewed operation, never inside an automatic seed/cutover. Rerun/Backfill and old Audit History must be interpreted with source boundaries in mind.
- RDS SQL Server Express caps each database at 10 GB; avoid the previous 10M x two-table 512-byte benchmark by default. Check source size and billing before scaling up.
- RDS needs network reachability from the selected Fabric gateway/network. Never expose port 1433 to the entire internet; use the narrowest access path available.
- **Static JSON/SQL checks are not Fabric runtime acceptance**. Confirm Basic/TLS, Query, Table, partition strategies and incremental semantics before PROD.
