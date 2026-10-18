<h1 align="center">Metadata-Driven Pipelines in Microsoft Fabric</h1>

<p align="center">
  <strong>Configuration-driven ingestion with guarded checkpoints, auditable runs, and failure-aware recovery.</strong>
</p>

<p align="center">
  <img alt="Microsoft Fabric Data Pipelines" src="https://img.shields.io/badge/Microsoft%20Fabric-Data%20Pipelines-5B4B91?style=flat-square" />
  <img alt="Fabric SQL Database" src="https://img.shields.io/badge/Control-Fabric%20SQL%20Database-4C6487?style=flat-square" />
  <img alt="SQL Server and SFTP sources" src="https://img.shields.io/badge/Sources-SQL%20Server%20%2B%20SFTP-526B82?style=flat-square" />
  <img alt="Lakehouse Delta destination" src="https://img.shields.io/badge/Target-Lakehouse%20Delta-397E78?style=flat-square" />
</p>

<p align="center">
  <a href="#architecture">Architecture</a> ·
  <a href="#design-highlights">Design highlights</a> ·
  <a href="#how-the-framework-works">How it works</a> ·
  <a href="#explore-the-implementation">Documentation</a> ·
  <a href="#run-the-example">Run the example</a>
</p>

Separate pipelines work well for a few source objects. As the number of objects grows, however, duplicated routing, checkpoint, and recovery logic becomes harder to maintain consistently.

This repository implements **metadata-driven batch ingestion using Microsoft Fabric Data Pipelines**. Shared pipelines read configuration tables to decide which source objects to ingest, how to process them, and where to write the results. This reduces repeated pipeline logic while keeping checkpoint management, auditing, and failure recovery consistent across objects.

The implementation uses **SQL Server tables and CSV files from SFTP** as example sources, writing to **Bronze Delta tables in a Fabric Lakehouse**. It includes reusable orchestration, incremental state management, audit logging, and failure recovery. A [Fabric Variable Library](docs/operations/variable-library-environment-binding.md) keeps key environment-specific runtime bindings separate from pipeline logic.

## Architecture

![Metadata-driven ingestion architecture in Microsoft Fabric. SQL Database stores configuration and checkpoints; shared pipelines select, dispatch, and route objects to Database or File ingestion. Both paths support FULL and INCREMENTAL loads, with SQL Server copying directly to Bronze and SFTP loading CSV files through Landing and a Notebook.](docs/assets/architecture-overview.svg)

*One shared orchestration flow selects and routes ingestion requests to Database or File adapters. Both paths support FULL and INCREMENTAL loads: SQL Server copies directly into Bronze; SFTP stages CSV files in Landing for Notebook parsing before the Bronze append.*

Fabric SQL Database is the **control layer**: it holds source configurations, the last saved checkpoint for incremental loads (a **watermark**), and the results recorded for completed object runs. The diagram keeps audit updates, guarded checkpoint changes, and failure recovery at a conceptual level rather than showing every activity or failure branch.

See [Architecture & Design Decisions](docs/architecture/framework-overview.md) for the full pipeline structure, design choices, and trade-offs.

## Design highlights

- **Metadata-backed routing.** SQL configuration selects source objects and load strategies; shared pipelines dispatch each request to a source-specific adapter rather than duplicating a pipeline per object.
- **Guarded incremental state.** Operational watermarks advance only after eligible, successfully finalized REGULAR incremental runs. BACKFILL and no-new-data SKIPPED runs do not advance the checkpoint.
- **Failure-aware writes.** Cleanup is scoped to an individual object execution, while uncertain SQL finalization outcomes are reconciled before destructive recovery. Bronze and the SQL control database are not one distributed transaction.
- **Inspectable operations.** Fabric Monitor shows pipeline execution; SQL audit records and the Power BI report show persisted object results, with explicit visibility limits.

## How the framework works

| Step | What happens |
| --- | --- |
| **1. Configure sources** | `control.ingestion_config` defines each source object, its DATABASE or FILE ingestion pattern, FULL or INCREMENTAL load strategy, and Bronze target. `control.connection_settings` maps logical connection references. |
| **2. Select and dispatch** | `pl_ingest_orchestrator` selects all active configurations, one source system, or explicit object requests. A paginator and dispatcher pass the selected objects into the shared processing flow. |
| **3. Route each object** | `pl_ingest_object_controller` reads the configuration. The DATABASE or FILE router then calls the matching SQL Server or SFTP adapter. The same orchestration structure serves different objects. |
| **4. Load into Bronze** | For SQL Server, a Fabric Copy activity reads a SQL query for a full table load or a timestamp-based incremental window. For SFTP, Binary Copy moves CSV files to Landing before a Notebook parses them and appends Delta rows. |
| **5. Record results and recover** | The framework records each completed object's outcome in `audit.ingestion_log`. Successful regular incremental runs can safely update their watermark; backfills and no-new-data runs do not. Selected failure paths remove data written by the affected execution without deleting other successful batches. |
| **6. Inspect runs** | **Fabric Monitor** shows pipeline activity and failures. The **Power BI Operations Report** summarizes recorded object results from SQL audit data; it does not replace Fabric Monitor for in-progress runs or failures before an object audit exists. |

**Why use shared pipelines?** Separate pipelines are still a good choice for small or highly specialized workloads. Metadata-driven orchestration becomes more useful when many objects follow similar ingestion rules, but the shared framework itself needs careful design and maintenance.

## Explore the implementation

You can read the design and code without setting up a Fabric workspace. For a guided route through the project, start with the [step-by-step learning guide](docs/guides/learning-path.md). Or choose a topic:

| What you want to understand | Where to start |
| --- | --- |
| Why the architecture is structured this way | [Architecture & Design Decisions](docs/architecture/framework-overview.md) |
| How source configuration and orchestration work | [Control Plane](docs/guides/control-plane.md) · [Pipeline Orchestration](docs/guides/pipeline-orchestration.md) |
| How a SQL Server table reaches Bronze | [SQL Server Ingestion](docs/guides/sql-server-database-ingestion.md) |
| How SFTP files move through Landing and Bronze | [SFTP Ingestion](docs/guides/sftp-file-ingestion.md) |
| How SQL Server Copy partitioning and parallelism are designed | [Copy Performance Strategy](docs/architecture/database-copy-performance.md) |
| How Fabric limits and environment bindings affect deployment | [Fabric Limits](docs/architecture/fabric-data-factory-limits.md) · [Environment Bindings](docs/operations/variable-library-environment-binding.md) |
| How incremental checkpoints and recovery work | [Incremental Watermarks](docs/architecture/generic-incremental-watermark.md) · [Failure Cleanup](docs/operations/bronze-compensating-cleanup.md) |
| What the monitoring report can show | [Operations Monitoring](docs/operations/monitoring-report.md) |
| What was observed in DEV performance experiments | [Benchmark Evidence](docs/benchmarks/evidence-and-test-plan.md) |

The `fabric/` directory contains the tracked Fabric pipeline, Notebook, SQL Database, Lakehouse, and Power BI item definitions. The `scripts/` directory contains SQL setup scripts and sample data.

## Run the example

To reproduce the sample, follow the [fresh DEV workspace setup guide](docs/operations/environment-rebuild.md) and [SQL setup and sample data order](scripts/RUN_ORDER.md). The runbook targets a new, empty DEV workspace. Deployments to other environments require their own connections, permissions, item bindings, and validation; importing Git definitions alone is not sufficient.

Once the sources and Fabric items are configured, start `pl_ingest_orchestrator`. For example, to select the active SFTP example objects:

```text
p_run_requests = []
p_source_system = "LOGISTICS_VENDOR"
```

The orchestrator selects the objects and invokes the child pipelines for you. After a run, check its activities in **Fabric Monitor**, then inspect `audit.ingestion_log` and the **Power BI Operations Report** for recorded results. The [SFTP walkthrough](docs/guides/sftp-file-ingestion.md) shows how to compare Landing, Bronze, and watermark state.

If you need demo source services, [the optional EC2/Docker Compose setup](infrastructure/source/README.md) describes the SQL Server and SFTP environment used for development. Review its environment-specific settings and safety notes before reusing it; it is not a one-command setup requirement for reading this project.

**Note:** The implemented source adapters cover SQL Server and SFTP. Other connectors and broader scheduling or concurrency policies would need additional design; see [Architecture & Design Decisions](docs/architecture/framework-overview.md).

**License:** No license is currently included. Public access does not by itself grant reuse or redistribution rights.
