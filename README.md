# fabric-metadata-driven-ingestion

## Architecture

- [Fabric Data Factory limits and framework guardrails](docs/architecture/fabric-data-factory-limits.md) — platform limits and framework design guardrails.
- [Database copy performance strategy](docs/architecture/database-copy-performance.md) — metadata-driven dynamic-range partitioning and evidence-based parallel-copy overrides.
- [Azure SQL copy benchmark](scripts/benchmark/README.md) — permanent 10M-row unpartitioned/physically-partitioned fixtures for NONE vs DYNAMIC_RANGE vs PHYSICAL_PARTITIONS testing.
- [Source metadata convention](docs/architecture/source-metadata-convention.md) — DATABASE table/view identity, stable FILE feeds, physical filename selection, and future API ownership.
- [File ingestion design](docs/architecture/file-ingestion-design.md) — SFTP Landing/Bronze design, recursive ingestion, watermarking, and reusable file loader.
- [Pipeline activity naming](docs/architecture/pipeline-activity-naming.md) — naming and pipeline-vs-notebook responsibility boundaries.

## Operations

- [Bronze compensating cleanup](docs/operations/bronze-compensating-cleanup.md) — defines the Bronze invariant: every successful REGULAR/BACKFILL execution appends a new immutable batch; deletion is limited to compensating cleanup of the current failed batch.
- [Retry, rerun, and backfill semantics](docs/operations/retry-rerun-backfill.md) — defines `run_type` (REGULAR/BACKFILL) independently from configured `load_strategy` (FULL/INCREMENTAL), including FULL and INCREMENTAL backfill behavior.
- [Top-level run request examples](docs/operations/run-request-examples.md) — run all active configs or submit an explicit mixed REGULAR/BACKFILL request array.
- [Orchestrator failure alerting](docs/operations/orchestrator-failure-alerting.md) — one pipeline-level failure notification boundary without notification activities in every child pipeline.
