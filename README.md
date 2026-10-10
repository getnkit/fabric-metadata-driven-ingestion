# fabric-metadata-driven-ingestion

The current relational demo source is **SQL Server 2022 Developer on Ubuntu EC2** using Fabric's generic **SQL Server** connector; the Control Plane remains a separate **Fabric SQL Database**. Connection type: `SQL_SERVER`, logical source ref: `SQL_SERVER_ECOMMERCE`. Fresh installations use `scripts/control/03_seed_connection_settings.sql` to register source and target connections.

## EC2 Source Infrastructure

- [Docker Compose source stack](infrastructure/source/README.md) — SQL Server 2022 Developer + SFTP on one EC2 host, environment template, persistent SFTP host identity and safe deployment/upload instructions.

## Starter Kit — Fresh Installation

This repository tracks the **current** Microsoft Fabric ingestion framework,
not a chain of historical upgrade patches.

1. [Starter Kit run order](scripts/RUN_ORDER.md): prepare Fabric items,
   four Variable Library runtime bindings, core SQL, and optional demo fixtures.
2. **Mandatory Control Plane scripts:** `01_create_control_schema.sql` →
   `02_create_control_procedures.sql` →
   `99_verify_control_plane.sql`.
3. **Optional DEV demo only:** `03_seed_connection_settings.sql` and
   `04_seed_ingestion_metadata.sql` (SQL Server 2022 Developer on EC2 + SFTP examples).
4. [SQL Control Plane baseline](docs/operations/sql-control-plane-hardening.md)
   describes constraints, non-destructive bootstrap and release gates.

**Note:** Installation scripts do not upgrade existing populated Control Databases. Review migrations separately.

## Architecture

- [Fabric Data Factory limits and framework guardrails](docs/architecture/fabric-data-factory-limits.md) — platform limits and framework design guardrails.
- [Database copy performance strategy](docs/architecture/database-copy-performance.md) — metadata-driven dynamic-range partitioning and evidence-based parallel-copy overrides.
- [SQL Server 2022 Developer on EC2 copy benchmark](scripts/source/benchmark-db/README.md) — 10M-row per table unpartitioned/physically-partitioned fixtures for NONE vs DYNAMIC_RANGE vs PHYSICAL_PARTITIONS testing.
- [File ingestion design](docs/architecture/file-ingestion-design.md) — SFTP Landing/Bronze design, recursive ingestion, watermarking, and reusable file loader.
- [Pipeline activity naming](docs/architecture/pipeline-activity-naming.md) — naming and pipeline-vs-notebook responsibility boundaries.

## Operations

- [Bronze compensating cleanup](docs/operations/bronze-compensating-cleanup.md) — defines the Bronze invariant: every successful REGULAR/BACKFILL execution appends a new immutable batch; deletion is limited to compensating cleanup of the current failed batch.
- [Retry, rerun, and backfill semantics](docs/operations/retry-rerun-backfill.md) — defines `run_type` (REGULAR/BACKFILL) independently from configured `load_strategy` (FULL/INCREMENTAL), including FULL and INCREMENTAL backfill behavior.
- [Top-level run request examples](docs/operations/run-request-examples.md) — run all active configs or submit an explicit mixed REGULAR/BACKFILL request array.
- [Orchestrator failure alerting](docs/operations/orchestrator-failure-alerting.md) — one pipeline-level failure notification boundary without notification activities in every child pipeline.
