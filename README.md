# fabric-metadata-driven-ingestion

## Starter Kit — Fresh Installation

This repository tracks the **current** Microsoft Fabric ingestion framework,
not a chain of historical upgrade patches.

1. [Starter Kit run order](scripts/RUN_ORDER.md): prepare Fabric items,
   four Variable Library connections, core SQL, and optional demo fixtures.
2. **Mandatory Control Plane scripts:** `01_create_control_schema.sql` →
   `02_create_control_procedures.sql` →
   `99_verify_control_plane.sql`.
3. **Optional DEV demo only:** `03_seed_connection_settings.sql` and
   `04_seed_ingestion_metadata.sql` (Azure SQL + SFTP examples).
4. [SQL Control Plane baseline](docs/operations/sql-control-plane-hardening.md)
   describes constraints, non-destructive bootstrap and release gates.

`scripts/control/migrations/` is intentionally absent from the Starter Kit:
old upgrades `001–011` remain available in
[pre-cleanup Git history](https://github.com/getnkit/fabric-metadata-driven-ingestion/tree/bf04ff6e67ed365c58adb8c07b94e1256b005bd1/scripts/control/migrations).
**Do not run fresh-install SQL as a substitute for upgrading a populated
older database.** Existing environments need a reviewed targeted migration.

## Architecture

- [Fabric Data Factory limits and framework guardrails](docs/architecture/fabric-data-factory-limits.md) — platform limits and framework design guardrails.
- [Database copy performance strategy](docs/architecture/database-copy-performance.md) — metadata-driven dynamic-range partitioning and evidence-based parallel-copy overrides.
- [Azure SQL copy benchmark](scripts/benchmark/README.md) — permanent 10M-row unpartitioned/physically-partitioned fixtures for NONE vs DYNAMIC_RANGE vs PHYSICAL_PARTITIONS testing.
- [File ingestion design](docs/architecture/file-ingestion-design.md) — SFTP Landing/Bronze design, recursive ingestion, watermarking, and reusable file loader.
- [Pipeline activity naming](docs/architecture/pipeline-activity-naming.md) — naming and pipeline-vs-notebook responsibility boundaries.

## Operations

- [Bronze compensating cleanup](docs/operations/bronze-compensating-cleanup.md) — defines the Bronze invariant: every successful REGULAR/BACKFILL execution appends a new immutable batch; deletion is limited to compensating cleanup of the current failed batch.
- [Retry, rerun, and backfill semantics](docs/operations/retry-rerun-backfill.md) — defines `run_type` (REGULAR/BACKFILL) independently from configured `load_strategy` (FULL/INCREMENTAL), including FULL and INCREMENTAL backfill behavior.
- [Top-level run request examples](docs/operations/run-request-examples.md) — run all active configs or submit an explicit mixed REGULAR/BACKFILL request array.
- [Orchestrator failure alerting](docs/operations/orchestrator-failure-alerting.md) — one pipeline-level failure notification boundary without notification activities in every child pipeline.
