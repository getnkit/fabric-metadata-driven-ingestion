# Metadata-Driven Pipelines in Microsoft Fabric

Building a separate pipeline for each table works well when the number of sources is small and requirements are stable. As more tables and source systems are added, however, repeating the same ingestion logic across many pipelines makes changes and maintenance harder.

This repository implements **metadata-driven batch ingestion using Microsoft Fabric Data Pipelines**. Shared pipelines read configuration tables to decide which source objects to ingest, how to process them, and where to write the results. This reduces repeated pipeline logic while keeping checkpoint management, auditing, and failure recovery consistent across objects.

The working implementation ingests **SQL Server tables and CSV files from SFTP** into **Bronze Delta tables in a Fabric Lakehouse**. It applies **production-oriented design patterns** to state management, run auditing, and failure recovery. The framework has been developed and tested in DEV; production use requires further validation and operational controls.

## Architecture

![Metadata-driven batch ingestion architecture: Fabric SQL Database manages configuration and run state; shared Fabric pipelines select and dispatch objects through ForEach and routing; SQL Server tables and SFTP CSV files follow separate Copy paths into Lakehouse Bronze, with the SFTP path using Landing and a Notebook.](docs/assets/architecture-overview.svg)

*Architecture overview: a shared orchestrator selects ingestion requests, optionally paginates configurations, and uses ForEach to dispatch objects to source-specific adapters. SQL Server data goes directly to Bronze through a Copy activity; SFTP CSV files are copied to Landing and parsed by a Notebook before reaching Bronze.*

Fabric SQL Database is the **control layer**: it holds source configurations, the last saved checkpoint for incremental loads (a **watermark**), and the results recorded for completed object runs. The diagram keeps audit updates, guarded checkpoint changes, and failure recovery at a conceptual level rather than showing every activity or failure branch.

See [Architecture & Design Decisions](docs/architecture/framework-overview.md) for the full pipeline structure, design choices, and trade-offs.

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
| How incremental checkpoints and recovery work | [Incremental Watermarks](docs/architecture/generic-incremental-watermark.md) · [Failure Cleanup](docs/operations/bronze-compensating-cleanup.md) |
| What the monitoring report can show | [Operations Monitoring](docs/operations/monitoring-report.md) |
| What was observed in DEV performance experiments | [Benchmark Evidence](docs/benchmarks/evidence-and-test-plan.md) |

The `fabric/` directory contains the tracked Fabric pipeline, Notebook, SQL Database, Lakehouse, and Power BI item definitions. The `scripts/` directory contains SQL setup scripts and sample data.

## Try the DEV example

Start with [setting up a fresh DEV environment](docs/operations/environment-rebuild.md), then follow the [SQL setup and demo data order](scripts/RUN_ORDER.md). A new workspace needs its own connections, permissions, and environment-specific IDs; importing definitions from Git alone is not enough.

Once the sources and Fabric items are configured, start `pl_ingest_orchestrator`. For example, to select the active SFTP example objects:

```text
p_run_requests = []
p_source_system = "LOGISTICS_VENDOR"
```

The orchestrator selects the objects and invokes the child pipelines for you. After a run, check its activities in **Fabric Monitor**, then inspect `audit.ingestion_log` and the **Power BI Operations Report** for recorded results. The [SFTP walkthrough](docs/guides/sftp-file-ingestion.md) shows how to compare Landing, Bronze, and watermark state.

If you need demo source services, [the optional EC2/Docker Compose setup](infrastructure/source/README.md) describes the SQL Server and SFTP environment used for development. Review its environment-specific settings and safety notes before reusing it; it is not a one-command setup requirement for reading this project.

**Note:** This example focuses on batch ingestion from SQL Server and SFTP. Other connectors and broader scheduling or concurrency policies would need additional design; see [Architecture & Design Decisions](docs/architecture/framework-overview.md).

**License:** No license is currently included. Public access does not by itself grant reuse or redistribution rights.
