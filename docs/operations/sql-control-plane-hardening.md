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
| `control.usp_finalize_ingestion_run` | Transactional final audit + guarded state advancement; exact terminal-outcome retry idempotence (reject mismatched retry) |
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
If running sample SQL Server/SFTP workloads, configure the three logical
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

## Release checks

- `99_verify_control_plane.sql` completes without THROW and all
  tracked constraints are enabled/trusted.
- SQL Project table column names/types and key definitions match the
  target environment; verify via schema diff before UAT/PROD.
- `pl_ingest_orchestrator` works with `vl_ingestion_connections`.
- SQL Server 2022 Developer on EC2 FULL / INCREMENTAL and SFTP FILE FULL / INCREMENTAL pass
  REGULAR/BACKFILL, SKIPPED, failure compensation and checkpoint
  concurrency acceptance.
- No demo seed runs against unrelated production metadata or resets
  a persisted Watermark State.
- Inspect Fabric-exported SQL Project security principals separately:
  workspace-specific user/SID and schema ownership must be reviewed
  for a new environment; do not modify them during routine Control/Audit reseeding.

