# Technical Learning Path — Metadata-Driven Batch Ingestion

This guide helps readers learn from the **implemented Microsoft Fabric
framework**, in a recommended order. It is not just a high-level architecture
diagram: each step points to the SQL scripts, Pipeline definitions and
Notebooks that implement the behavior.

**Platform scope:** Microsoft Fabric Data Factory, Fabric SQL Database and
Lakehouse Bronze. Many design principles are relevant to Azure Data Factory,
but its deployment formats and some activity features differ. The repo does
not claim to contain deployable ADF assets.

## 1 — Understand the architectural problem

Start with [Architecture & Design Decisions](../architecture/framework-overview.md).
Without metadata-driven orchestration, a per-table/per-file ingestion estate
duplicates routing, watermark decisions, audit and recovery mechanics.

Trace three boundaries: **Control Plane** (config/state/audit),
**Orchestration Plane** (routing/validation/dispatch), and **Data Plane**
(source -> Landing/Bronze). They have different responsibilities and do not
share an end-to-end distributed transaction.

**Exercise:** Explain why SQL Database state should not be confused with
Delta rows, and what can happen between Bronze Commit and SQL Finalization.

## 2 — Build a mental model of metadata

Read [Control schema bootstrap](../../scripts/control/01_create_control_schema.sql),
[connection metadata seed](../../scripts/control/03_seed_connection_settings.sql),
and [ingestion metadata seed](../../scripts/control/04_seed_ingestion_metadata.sql).

Identify the purpose of `control.connection_settings`,
`control.ingestion_config`, `control.pipeline_watermarks`,
and `audit.ingestion_log`. Understand `ingestion_pattern`,
`load_strategy`, `source_conn_ref`, `target_conn_ref`,
`watermark_field`, `source_options` and `copy_options`.

The demo has six E-commerce DATABASE and two Logistics FILE
configurations. The source-specific execution contract lives in metadata;
the underlying executable Pipelines are shared.

**Exercise:** Find the FULL objects and INCREMENTAL objects. Explain why
FULL configs have no Watermark checkpoint.

## 3 — Follow the request through orchestration

Open the actual JSON definitions under:
- `fabric/pl_ingest_orchestrator.DataPipeline/`
- `fabric/pl_ingest_config_paginator.DataPipeline/`
- `fabric/pl_ingest_config_dispatcher.DataPipeline/`
- `fabric/pl_ingest_object_controller.DataPipeline/`
- `fabric/pl_ingest_database_router.DataPipeline/`
- `fabric/pl_ingest_file_router.DataPipeline/`

Use [Run Request Examples](../operations/run-request-examples.md).
There are three entry shapes: all active configs, active configs scoped to
one source system, or an explicit list of configs with run types.
Only the **top-level Orchestrator** is the supported external entry point.

**Exercise:** Trace a source-system-scoped request, then trace an explicit
single-object BACKFILL request. Why do they reach the same Dispatcher?

## 4 — Compare physical DATABASE and FILE adapters

**DATABASE:** Read [Database Extensibility](../architecture/database-ingestion-extensibility.md)
and [Copy Strategy](../architecture/database-copy-performance.md).
SQL Server FULL/INCREMENTAL uses native **Query-mode Copy** to append to
Lakehouse Bronze. Connector execution options include `NONE` or
`DYNAMIC_RANGE` partitioning and an optional positive `parallel_copies`
override.

**FILE:** Start with the [SFTP File Ingestion Guide](sftp-file-ingestion.md),
then read [File Ingestion](../architecture/file-ingestion-design.md) for more detail.
SFTP files are copied in Binary mode to execution-scoped Lakehouse Files
Landing. `nb_load_file_landing_to_bronze.Notebook` parses and appends
**DELIMITED_TEXT only**. JSON/Parquet file ingestion is not implemented.

**Exercise:** Why is the relational Copy path separate from Notebook-based
Landing parsing, and what data does the Landing layer preserve?

## 5 — Reason about incremental state and BACKFILL

Read [Generic Incremental Watermark](../architecture/generic-incremental-watermark.md)
and [Retry/Rerun/Backfill](../operations/retry-rerun-backfill.md).
A durable LOW and an execution HIGH define the processing boundary.
On eligible REGULAR/INCREMENTAL success, the SQL Finalizer can advance
the Watermark with optimistic protection. BACKFILL does **not** advance
the operational checkpoint; no-new-data SKIPPED does **not** advance it.

Inspect the [Finalizer procedure](../../fabric/sqldb_ingestion_control.SQLDatabase/control/StoredProcedures/usp_finalize_ingestion_run.sql).

**Exercise:** Predict Audit Status and Watermark behavior for DATABASE
REGULAR INCREMENTAL HIGH=LOW and a valid historical INCREMENTAL BACKFILL.

## 6 — Understand failure compensation versus Delta atomicity

Read [Bronze Compensating Cleanup](../operations/bronze-compensating-cleanup.md)
and [Retry Policy](../architecture/retry-policy.md). A single Delta write
has transaction atomicity, but the *whole pipeline* spans distinct
storage and SQL finalization boundaries. A Copy/Notebook can fail
after a Bronze commit; Finalization can also have an uncertain outcome.

Find the three corresponding implementations in `fabric/`:
`nb_cleanup_bronze_batch_rows.Notebook`,
`nb_cleanup_landing_batch_files.Notebook`, and
`pl_ingest_incremental_finalize_recovery.DataPipeline`.

**Exercise:** Why does Bronze Cleanup use both `_batch_id` and
`_pipeline_run_id`? Why must a failed `sp_finalize_success` not trigger
a blind deletion without checking durable finalization?

## 7 — Monitor only what the Audit Plane can observe

Read [Operational Monitoring](../operations/monitoring-report.md) and
[monitoring SQL views](../../scripts/monitoring/01_create_monitoring_views.sql).
The official Power BI Report and Semantic Model are under `fabric/`.
They use DirectQuery over **terminal object audit**, not an all-knowing live
master-pipeline status service.

**Exercise:** Will a master failure *before any object audit* appear in the
Power BI Object History? Why or why not?

## 8 — Try a fresh DEV install when appropriate

Use the [Environment Rebuild Runbook](../operations/environment-rebuild.md),
[SQL Run Order](../../scripts/RUN_ORDER.md), and
[EC2 source setup](../../infrastructure/source/README.md).
Cloud Connections, Fabric IDs, permissions and Power BI SQL endpoints must
be rebound for a new workspace. Git is not a backup of prior Bronze rows,
watermarks, historical audit or credentials.

For factual DEV observations and a reproducible benchmark design, read
[Benchmark Evidence & Test Plan](../benchmarks/evidence-and-test-plan.md).

## How to use this material

| Your goal | Suggested steps |
| --- | --- |
| Understand metadata design and orchestration | 1–3 |
| Implement SQL Server or SFTP batch adapters | 2–4 |
| Reason about Watermark, SKIPPED and BACKFILL | 2, 5 |
| Handle failures across Bronze/SQL | 5–6 |
| Build audit-backed operations visibility | 7 |
| Set up the demo / evaluate benchmark evidence | 8 |

**Publication note:** The source is publicly viewable, but there is
currently **no open-source license**. Visibility does not itself grant
permission to copy, redistribute or relicense code. Confirm ownership
and confidentiality clearance before granting broader reuse rights.
