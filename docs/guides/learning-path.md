# Technical Learning Path — Metadata-Driven Pipelines

You can understand the framework without provisioning Fabric. Choose a route below, then follow the numbered
walkthrough only as far as you need. Each step points to the canonical explanation and, when useful, the checked-in
implementation.

**Scope:** Microsoft Fabric Data Pipelines, Fabric SQL Database, Lakehouse Bronze; implemented batch sources are SQL
Server and SFTP. The repository does **not** contain deployable Azure Data Factory assets or working
Oracle/PostgreSQL/API/CDC/streaming adapters.

## Choose a reading route

| Goal | Read |
| --- | --- |
| **Portfolio / architecture scan** | [Architecture](../architecture/framework-overview.md) → [Evidence & limitations](../benchmarks/evidence-and-test-plan.md) |
| **Follow an actual ingestion request** | Steps **1–4** below; choose SQL Server or SFTP |
| **Understand production-style safety decisions** | Steps **5–7**: watermark, retry/compensation, audit visibility |
| **Reproduce the DEV demo** | Step **8**, then follow the operator runbooks (not the design documents) |

## 1 — Understand the architectural problem

**Read:** [Architecture & Design Decisions](../architecture/framework-overview.md).

Focus on the **Control & Audit Plane** (config/state/terminal audit), **Orchestration Plane**
(selection/validation/routing), and **Data Plane** (source → Landing/Bronze). These are logical responsibilities
within one Fabric-based framework, not isolated deployed platforms. The Bronze write and Control SQL finalization
are not one distributed transaction.

**Check yourself:** What can happen between a Bronze commit and SQL finalization?

## 2 — Inspect the metadata

**Read:** [Control Plane](control-plane.md). Inspect the read-only example queries for
`control.connection_settings`, `control.ingestion_config`, `control.pipeline_watermarks`, and
`audit.ingestion_log`.

**Inspect the definitions:** The [Fabric SQL Database Project](../../fabric/sqldb_ingestion_control.SQLDatabase/)
is the schema source of truth. The [Control schema bootstrap](../../scripts/control/01_create_control_schema.sql)
creates missing objects for a fresh install; it does not migrate an existing schema. The
[connection seed](../../scripts/control/03_seed_connection_settings.sql) and
[ingestion seed](../../scripts/control/04_seed_ingestion_metadata.sql) supply DEV examples: six E-commerce DATABASE
objects and two Logistics FILE objects.

**Check yourself:** Which configs are FULL versus INCREMENTAL, and why does FULL have no persistent checkpoint?

## 3 — Trace the request through orchestration

**Read:** [Pipeline Orchestration](pipeline-orchestration.md) and [Run Request Examples](../operations/run-request-examples.md).

Inspect `fabric/pl_ingest_orchestrator.DataPipeline/`, `pl_ingest_config_paginator.DataPipeline/`,
`pl_ingest_config_dispatcher.DataPipeline/`, `pl_ingest_object_controller.DataPipeline/`, and the DATABASE/FILE
router definitions under `fabric/`. Only the top-level Orchestrator is a supported external entry point.

**Check yourself:** Why do explicit requests and source-scoped all-active requests reach the same Dispatcher?

## 4 — Follow one physical ingestion path

**DATABASE:** [SQL Server Guide](sql-server-database-ingestion.md) explains Query-mode Copy for FULL and timestamp
INCREMENTAL; [Copy Performance](../architecture/database-copy-performance.md) explains supported `NONE` and
`DYNAMIC_RANGE` partition settings and benchmark limits.

**FILE:** [SFTP Guide](sftp-file-ingestion.md) traces Binary Copy into execution-scoped Landing and the
`nb_load_file_landing_to_bronze` Notebook; [FILE Design](../architecture/file-ingestion-design.md) records the
connector and parsing decisions. Only `DELIMITED_TEXT` is implemented.

**Check yourself:** Why is the SQL Server path direct-to-Bronze while SFTP keeps a raw Landing copy?

## 5 — Reason about incremental state

**Read:** [Generic Incremental Watermark](../architecture/generic-incremental-watermark.md) and [Retry/Rerun/Backfill](../operations/retry-rerun-backfill.md).

Inspect [the SQL finalizer procedure](../../fabric/sqldb_ingestion_control.SQLDatabase/control/StoredProcedures/usp_finalize_ingestion_run.sql).
A normal incremental run derives a LOW/HIGH boundary; an eligible successful REGULAR run may advance the
checkpoint with optimistic protection. BACKFILL and no-new-data SKIPPED do not advance it.

**Check yourself:** Predict audit and watermark behavior for DATABASE REGULAR INCREMENTAL with HIGH = LOW, and for an incremental historical BACKFILL.

## 6 — Inspect failure compensation and retries

**Read:** [Bronze Compensating Cleanup](../operations/bronze-compensating-cleanup.md) and the [retry matrix](../operations/retry-rerun-backfill.md#retry-policy-by-side-effect).

Inspect `nb_cleanup_bronze_batch_rows.Notebook`, `nb_cleanup_landing_batch_files.Notebook`, and
`pl_ingest_incremental_finalize_recovery.DataPipeline` in `fabric/`. A failed Copy/Notebook or Finalizer activity
does not prove whether a durable write committed.

**Check yourself:** Why does cleanup match both `_batch_id` and `_pipeline_run_id`, and why is blind cleanup unsafe after a failed success Finalizer?

## 7 — Understand what monitoring proves

**Read:** [Operations Monitoring](../operations/monitoring-report.md) and [SQL monitoring views](../../scripts/monitoring/01_create_monitoring_views.sql).

The checked-in Power BI report/semantic model use DirectQuery over terminal **object-level audit**. They cannot show
in-progress runs or failures before an object audit. Optional Activator alert delivery has not been independently
verified.

**Check yourself:** Would an early master-pipeline failure appear in Power BI Object History?

## 8 — Rebuild or benchmark when needed

**For operators:** [Environment Rebuild](../operations/environment-rebuild.md) covers new-workspace bindings and
verification; [SQL Run Order](../../scripts/RUN_ORDER.md) covers the executable Control SQL / demo seed sequence;
[EC2/SFTP source setup](../../infra/source/README.md) handles optional source services. Do not treat Git as a backup
of historic Bronze rows, watermarks, audits, or secrets.

**For reviewers:** [Evidence & Benchmark Plan](../benchmarks/evidence-and-test-plan.md) distinguishes observed DEV
behavior from outstanding tests. [Fabric Data Factory Limits](../architecture/fabric-data-factory-limits.md)
documents platform guardrails; [Variable Library Bindings](../operations/variable-library-environment-binding.md)
documents environment-specific IDs.

**Check yourself:** Which claims can be confirmed from Git definitions, and which require a live DEV execution or recipient-delivery check?

---

**Use this as a navigation guide, not another implementation specification.** For details, use the linked topic
guide; for exact behavior, inspect the corresponding Fabric/SQL definitions and runtime evidence. Diagrams alone do
not establish test completion.
