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

On the Ubuntu EC2 host, connect to the SQL Server 2022 Developer container as the database administrator and run `CREATE DATABASE [sql_ecommerce_db];` once. Select that database in the SQL client. Then prepare the demo source:

```text
scripts/source/01_create_source_schema.sql
scripts/source/02_generate_source_data.sql
scripts/security/01_grant_fabric_basic_source_read.sql
```

The SQL Server security script creates a server-level SQL LOGIN in `master`, maps a database USER in `sql_ecommerce_db` and grants least-privilege read access. Replace the password placeholder locally, never commit it. Run the script with a SQL Server administrator permitted to create logins. Expected initial demo row counts:

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

The connection seed creates logical `SQL_SERVER_ECOMMERCE`,
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

Create a Fabric **SQL Server** connection (`cn_src_sql_server`) with Basic authentication, the approved EC2 SQL Server host/port 1433, and database `sql_ecommerce_db`. Use the read-only login from the security script; test connectivity and TLS/network restrictions. Populate `@SourceConnectionId` in seed `03` using **this** connector's ID. The source database is bound in the Fabric Connection; metadata JSON contains its `connectionId` only. Source SQL Server is separate from the Fabric Control SQL Database.

Run only `pl_ingest_orchestrator` as the standard entry point:
`p_run_requests = []` runs all active configs as REGULAR; a non-empty
array runs explicit `config_id` and `run_type` requests. Backfill is
an explicit request with LOW/HIGH for INCREMENTAL. Supported run types
are REGULAR and BACKFILL; `load_strategy` remains FULL/INCREMENTAL.

- DATABASE: SQL Server 2022 Developer on EC2 reads directly into Bronze Delta; source-derived
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

The independent 10M-row-per-table performance fixtures and scenario scripts remain in
`scripts/benchmark/` with their own [README](benchmark/README.md).
Run them in a **separate database on the same EC2 SQL Server instance** (`sql_ingestion_benchmark`). The default is **10,000,000 rows in each of two tables** (`CHAR(512)` payload), using SQL Server Developer Edition for DEV/test only. Watch EBS free space, SQL data/log files, CPU/memory and transfer usage. Benchmark configs are inactive by default and **not part of the starter installation**.

## Release note

The SQL Database Project may include Fabric-exported, workspace-specific
security principals and schema owners. **Do not blindly deploy these
identities across environments**; review SQL Project security and
permissions during provisioning. This cleanup intentionally leaves those
security artifacts untouched to avoid unintended ownership or DROP USER
changes in the existing DEV database.

## G. Generic SQL Server connection cutover (existing DEV only)

- New route: `SQL_SERVER|FULL` and `SQL_SERVER|INCREMENTAL`.
- New logical refs: `SQL_SERVER_ECOMMERCE` and optional `SQL_SERVER_INGESTION_BENCHMARK`. Preserve `source_system`, existing config IDs, target schemas, watermarks and audit history.
- Rename the three Fabric database workers via Git sync; their `.platform` `logicalId` values stay unchanged. **Verify Invoke Pipeline target rebinding** after sync.
- Create/test a **generic SQL Server** Fabric Connection for `sql_ecommerce_db` first. If the dedicated benchmark source already exists, create/test a separate Fabric SQL Server Connection for `sql_ingestion_benchmark` too.
- Set `@SourceConnectionId` and (if an old RDS benchmark ref exists) `@BenchmarkConnectionId` in [`scripts/operations/01_cutover_existing_dev_to_sql_server.sql`](operations/01_cutover_existing_dev_to_sql_server.sql); execute it in the **Fabric Control SQL Database**, NOT on EC2. It migrates Azure SQL/RDS demo references transactionally, leaving config IDs, `control.pipeline_watermarks` and audit rows intact. Then run `scripts/control/99_verify_control_plane.sql`.
- For fresh DEV SQL Control Database, run the standard seed scripts `03 -> 04` instead; **do not** run the cutover.
- The generic SQL Server Connector uses `SqlServerSource` and `SqlServerTable`; the database selection comes from the Fabric Connection. Verify Copy/Lookup and the actual connection-binding behavior in Fabric DEV.
- Repointing a logical source does **not** guarantee previous watermark LOW/HIGH values exist in the new EC2 database. Check against its `MAX(updated_at)` and available source history before enabling REGULAR, or explicitly plan a reviewed rebaseline. Never reset watermarks as a side effect of this cutover.
- Keep port 1433 limited to approved access. Use a private network or supported on-premises/VNet gateway when practical; do not expose it to `0.0.0.0/0`.
- **Static JSON/SQL checks are not Fabric runtime acceptance**. Confirm Basic/TLS, NONE/DYNAMIC_RANGE/PHYSICAL_PARTITIONS, FULL/INCREMENTAL, REGULAR/BACKFILL, Bronze, audit, watermarks and failure paths.
