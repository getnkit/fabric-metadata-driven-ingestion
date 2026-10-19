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
  <a href="#start-here">Start here</a> ·
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

- **Metadata-driven, reusable orchestration.** One Control Plane configures objects, connection references, FULL/INCREMENTAL strategy, and Bronze targets without a pipeline per table.
- **Safe checkpoint semantics.** Only an eligible successful REGULAR incremental run advances its watermark. BACKFILL and no-new-data SKIPPED leave the checkpoint unchanged.
- **Explicit failure boundaries.** Failed Bronze writes use execution-scoped compensation; an uncertain SQL finalizer result is reconciled before any cleanup.
- **Honest operations visibility.** Fabric Monitor shows pipeline execution; SQL audits and Power BI report **recorded terminal object outcomes**, not live master status.

The implemented examples are **SQL Server and SFTP batch ingestion only**. Other database vendors, file readers beyond `DELIMITED_TEXT`, CDC, and streaming are not implemented in this repository.

## How the framework works

| Stage | What happens |
| --- | --- |
| **Configure** | Fabric SQL Database holds `control.ingestion_config`, logical connections, incremental watermarks, and terminal object audits. |
| **Select and route** | `pl_ingest_orchestrator` accepts explicit requests or chooses active configurations (optionally source-scoped); a paginator, dispatcher, controller, and routers select the appropriate adapter. |
| **Load Bronze** | SQL Server uses query-mode Copy directly to Delta; SFTP uses Binary Copy into execution-scoped Lakehouse Files Landing, then a Notebook parses and appends Delta rows. |
| **Finalize and inspect** | The framework audits each object run and conditionally advances its watermark. Fabric Monitor shows execution; the SQL-backed Power BI report summarizes completed object audits. |

## Start here

You do **not** need a Fabric workspace to review the architecture and code. Choose a route rather than reading every document in order:

| Your goal | Recommended entry |
| --- | --- |
| **Get the design in one pass** | [Architecture & Design Decisions](docs/architecture/framework-overview.md) — orchestration, state, and trade-offs |
| **Understand how it works in code** | [Technical Learning Path](docs/guides/learning-path.md) — guided SQL Server/SFTP walkthroughs, then deeper references |
| **Rebuild a working DEV demo** | [Environment Rebuild](docs/operations/environment-rebuild.md) — new-workspace checklist, with the [SQL run order](scripts/RUN_ORDER.md) |
| **Check what was actually tested** | [DEV Evidence & Benchmark Plan](docs/benchmarks/evidence-and-test-plan.md) — observations versus outstanding validation |

The learning path also indexes the focused guides for Control Plane, pipeline routing, incremental processing, Copy tuning, failure recovery, and monitoring.

**Repository layout:** `fabric/` tracks Fabric Pipeline, Notebook, SQL Database, Lakehouse, Variable Library, and Power BI definitions; `scripts/` contains SQL setup and demo fixtures; `infra/` is the optional EC2/Docker Compose source environment. Git-tracked definitions are not a backup of Bronze rows, audit history, watermarks, or credentials.

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
