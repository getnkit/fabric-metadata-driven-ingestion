<h1 align="center">Metadata-Driven Pipelines in Microsoft Fabric</h1>

<p align="center">
  <strong>Configure ingestion for many source objects without building a separate pipeline for each one.</strong>
</p>

<p align="center">
  <img alt="Microsoft Fabric Data Pipelines" src="https://img.shields.io/badge/Microsoft%20Fabric-Data%20Pipelines-5B4B91?style=flat-square" />
  <img alt="Fabric SQL Database" src="https://img.shields.io/badge/Control-Fabric%20SQL%20Database-4C6487?style=flat-square" />
  <img alt="Lakehouse Delta destination" src="https://img.shields.io/badge/Target-Lakehouse%20Delta-397E78?style=flat-square" />
</p>

<p align="center">
  <a href="#architecture">Architecture</a> ·
  <a href="#design-highlights">Design highlights</a> ·
  <a href="#how-the-framework-works">How it works</a> ·
  <a href="#explore-the-implementation">Documentation</a> ·
  <a href="#run-the-example">Run the example</a>
</p>

Separate pipelines work well for a few source objects, but repeating the same load logic across many objects becomes harder to maintain.

This repository implements a **metadata-driven ingestion framework in Microsoft Fabric**. Instead of maintaining separate pipelines for individual source objects, the framework uses configuration tables to define what to ingest, how to process it, and where to write the results. Reusable orchestration routes each object through the appropriate ingestion path, with consistent watermark management and run auditing.

The repository demonstrates the framework with end-to-end **batch ingestion examples** for SQL Server tables and CSV files from SFTP. Both paths support FULL and INCREMENTAL loads into **Bronze Delta tables in a Fabric Lakehouse**.

## Architecture

![Metadata-driven ingestion architecture in Microsoft Fabric. SQL Database stores source configuration, watermarks, and object audit records; the orchestration layer routes requests through Database or File adapters, loading Bronze Delta tables.](docs/assets/architecture-overview.svg)

Fabric SQL Database stores source configurations, incremental checkpoints (**watermarks**), and run audits. Fabric Data Pipelines use this metadata to select an ingestion path for each source object and coordinate loading into Bronze Delta tables in the Lakehouse.

See [Architecture & Design Decisions](docs/architecture/framework-overview.md) for the pipeline structure and design trade-offs.

## Design highlights

- **Configuration-driven ingestion.** Source objects, ingestion patterns, load strategies, and Bronze targets are defined in metadata tables.
- **Watermark management.** Watermarks advance only after successful REGULAR incremental loads. BACKFILL and no-new-data SKIPPED runs leave them unchanged.
- **Audit and monitoring.** Fabric Monitor tracks pipeline execution; SQL audit tables and Power BI show recorded ingestion results.

## How the framework works

| Step | What happens |
| --- | --- |
| **1. Configure sources** | `control.ingestion_config` defines each source object, its DATABASE or FILE ingestion pattern, FULL or INCREMENTAL load strategy, and Bronze target. `control.connection_settings` maps logical references to source and target connections. |
| **2. Select and dispatch** | The orchestrator accepts explicit object requests or selects active configurations, optionally filtered by source system. A paginator reads active configurations in pages; the dispatcher passes each request to the controller. |
| **3. Route each object** | The controller checks each object's configuration and selects the DATABASE or FILE path. The router then invokes the adapter based on source connection type and load strategy. |
| **4. Load into Bronze** | For SQL Server, a Copy activity loads rows directly into Bronze using a full-table query or a timestamp-based incremental window. For SFTP, Binary Copy stages CSV files in Landing; a Notebook then parses and appends the rows to Bronze. |
| **5. Record results and update watermarks** | The framework records object-run outcomes in `audit.ingestion_log`. `control.pipeline_watermarks` stores incremental checkpoints, which advance only after successful REGULAR incremental loads. BACKFILL and no-new-data SKIPPED runs leave them unchanged. |
| **6. Inspect runs** | **Fabric Monitor** shows pipeline execution. The **Power BI Operations Report** summarizes recorded ingestion results from SQL audit data. |

## Explore the implementation

You can explore the design and code without setting up a Fabric workspace. Follow the [technical learning path](docs/guides/learning-path.md) for a guided walkthrough, or go straight to a topic below:

| What you want to understand | Where to start |
| --- | --- |
| Why the architecture is structured this way | [Architecture & Design Decisions](docs/architecture/framework-overview.md) |
| How source configurations are managed | [Control Plane](docs/guides/control-plane.md) |
| How ingestion requests are orchestrated and routed | [Pipeline Orchestration](docs/guides/pipeline-orchestration.md) |
| How SQL Server data is loaded into Bronze | [SQL Server Ingestion](docs/guides/sql-server-database-ingestion.md) |
| How SFTP files are staged in Landing and loaded into Bronze | [SFTP Ingestion](docs/guides/sftp-file-ingestion.md) |
| How SQL Server Copy partitioning and parallelism are designed | [Copy Performance Strategy](docs/architecture/database-copy-performance.md) |
| Fabric Data Factory limits and their impact on pipeline design | [Fabric Limits](docs/architecture/fabric-data-factory-limits.md) |
| How to configure connections across environments | [Environment Bindings](docs/operations/variable-library-environment-binding.md) |
| How incremental watermarks are managed | [Incremental Watermarks](docs/architecture/generic-incremental-watermark.md) |
| How failed ingestion writes are handled | [Failure Cleanup](docs/operations/bronze-compensating-cleanup.md) |
| What the monitoring report can show | [Operations Monitoring](docs/operations/monitoring-report.md) |
| What was tested in DEV and what remains unverified | [DEV Tests & Benchmarks](docs/benchmarks/evidence-and-test-plan.md) |

The `fabric/` directory contains Git-tracked Fabric item definitions, including pipelines, notebooks, SQL Database, Lakehouse, Variable Library, and Power BI assets. The `scripts/` directory contains SQL setup scripts and sample data. The `infra/` directory provides an optional EC2/Docker Compose setup for the SQL Server and SFTP example sources.

## Run the example

To reproduce the examples, follow the [workspace setup guide](docs/operations/environment-rebuild.md) and [SQL and sample-data setup sequence](scripts/RUN_ORDER.md). These instructions are intended for a new, empty DEV workspace and should not be used to overwrite an existing environment.

Once the sources and Fabric items are configured, run `pl_ingest_orchestrator`. For example, to select the active SFTP source objects:

```text
p_run_requests = []
p_source_system = "LOGISTICS_VENDOR"
```

The orchestrator selects matching objects and invokes the required child pipelines. After the run, inspect its activities in **Fabric Monitor**, then check `audit.ingestion_log` and the **Power BI Operations Report** for recorded results. The [SFTP walkthrough](docs/guides/sftp-file-ingestion.md) shows how to compare Landing, Bronze, and watermark state.

To set up the optional SQL Server and SFTP demo environment, see the [EC2/Docker Compose setup](infra/source/README.md). This environment is not required to explore the repository; review its configuration and security notes before deploying it.

## License

No license is currently included. Public access does not by itself grant reuse or redistribution rights.
