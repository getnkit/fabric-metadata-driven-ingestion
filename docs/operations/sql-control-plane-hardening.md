# SQL Control Plane — Current Starter Kit Baseline

This document describes the **current Personal SQL baseline**, not migration
history. The physical schema source of truth is
`fabric/sqldb_ingestion_control.SQLDatabase/`; the canonical quickstart is
[`scripts/RUN_ORDER.md`](../../scripts/RUN_ORDER.md).

## Control/Audit components

| Object | Contract |
| --- | --- |
| `control.connection_settings` | Three supported connection types; nonblank reference; object-root JSON |
| `control.ingestion_config` | Nonblank required metadata; DATABASE requires source_schema; FILE requires source_path, landing_path and file_format; optional JSON envelopes have object roots; INCREMENTAL requires a nonblank watermark field |
| `control.pipeline_watermarks` | One checkpoint per `ingestion_config_id`; nonblank field/value; no automatic reset; optimistic advancement only in `usp_finalize_ingestion_run` |
| `audit.ingestion_log` | One terminal result per child pipeline RunId; valid status/run type; nonnegative counts and duration; nonblank run identity; `landing_path` is the canonical physical audit column |
| `control.v_pipeline_watermarks` | Read-only combined view over state and configuration |
| `control.usp_finalize_ingestion_run` | Transactional final audit + guarded state advancement; retry idempotence |
| `control.usp_validate_run_requests` | Explicit request array/object/type/duplicate validation; rejects NULL envelope |

The FILE `file_format` CHECK explicitly requires a non-NULL value. SQL CHECK
may otherwise accept `UNKNOWN`. Although metadata permits
`DELIMITED_TEXT`, `PARQUET`, and `JSON`, the current **File Router**
implements `DELIMITED_TEXT` only; the other labels remain future capabilities.

## Canonical install scripts

Use `scripts/control/`:

```text
01_create_control_schema.sql       # Non-destructive four-table/view/index baseline
02_create_control_procedures.sql   # Both ingestion procedures (CREATE OR ALTER)
03_seed_connection_settings.sql    # Optional environment-specific DEV demo
04_seed_ingestion_metadata.sql     # Optional DEV demo config + missing initial state
99_verify_control_plane.sql       # Read-only schema verification
```

For a new empty Fabric SQL Database, run **01 → 02 → 99**.
If running sample RDS SQL Server/SFTP workloads, configure the three logical
Connection references and run demo **03 → 04 → 99** afterward. These
seeds are optional and **not** generic production metadata.

A fresh bootstrap intentionally does **not** drop or rebuild existing
tables. CREATE-IF-ABSENT is not a schema upgrade; it leaves old tables
unchanged. Script `99` checks four tables, view, two procedures, trusted
CHECK/FK constraints, PK/UQ and audit indexes. It is a structural
verification, not a complete column-by-column semantic schema diff.

Seed `04` preserves existing Watermark State records and initialises
only missing DATABASE/FILE INCREMENTAL states. It contains no historical
source-system rename or legacy FILE watermark reset branch.
A changed `watermark_field` must never silently reuse/reset a checkpoint.

## Existing DEV / historic upgrade scripts

Historical migration scripts `001–011` have already been used in this
project and are **not required to create the current baseline from scratch**.
They were removed from the current Starter Kit tree so fresh installation
contains no ad hoc historical patches. They remain recoverable from the
immutable pre-cleanup revision:

[Historical migrations — commit bf04ff6](https://github.com/getnkit/fabric-metadata-driven-ingestion/tree/bf04ff6e67ed365c58adb8c07b94e1256b005bd1/scripts/control/migrations)

Never replay the old migration sequence blindly on an existing environment.
First inspect its actual schema and data, pause ingestion, preserve/export
the checkpoint and audit rows, and plan a reviewed targeted upgrade.
In-place schema upgrades and SQL Project deployments must not race each
other. Avoid deploying a fresh-install package as a data migration.

DEV has been reported to pass constraint checks (12 upgraded constraints
enabled/trusted) and `99` returned the expected four table column counts.
That evidence confirms the reported structural state only; functional
negative tests, Source Copy, Notebook runtime and PROD portability
remain separate acceptance gates.

## Release checks

- `99_verify_control_plane.sql` completes without THROW and all
  tracked constraints are enabled/trusted.
- SQL Project table column names/types and key definitions match the
  target environment; verify via schema diff before UAT/PROD.
- `pl_ingest_orchestrator` works with `vl_ingestion_connections`.
- Amazon RDS for SQL Server FULL / INCREMENTAL and SFTP FILE FULL / INCREMENTAL pass
  REGULAR/BACKFILL, SKIPPED, failure compensation and checkpoint
  concurrency acceptance.
- No demo seed runs against unrelated production metadata or resets
  a persisted Watermark State.
- Inspect Fabric-exported SQL Project security principals separately:
  workspace-specific user/SID and schema ownership must be reviewed
  for a new environment; the cleanup intentionally does not mutate
  those security artifacts.

## Existing DEV connector cutover (Azure SQL -> RDS SQL Server)

Existing Fabric SQL Control DB may still have old`CK_connection_settings_type`
restricted to `AZURE_SQL`. After creating the RDS Fabric Connection, execute
[`scripts/operations/01_cutover_existing_dev_to_rds.sql`](../../scripts/operations/01_cutover_existing_dev_to_rds.sql)
with the new Fabric `connectionId`. It migrates the ECOMMERCE logical
Connection Ref from `AZSQL_ECOMMERCE` to `RDS_ECOMMERCE` inside a single
transaction, replacing the CHECK constraint with the current RDS/SFTP/Lakehouse
baseline. It leaves ingestion config IDs, Watermark State values, audit
history and source-boundary semantics unchanged. Check source continuity before
resuming REGULAR ingestion. It rejects unhandled legacy Azure SQL references
rather than silently redirecting unrelated sources.
