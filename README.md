<h1 align="center">Metadata-Driven Pipelines in Microsoft Fabric</h1>

<p align="center">
  <strong>Configure ingestion for many source objects without building a separate pipeline for each one.</strong>
</p>

<p align="center">
  <img alt="Control and Audit Plane: Fabric SQL Database" src="https://img.shields.io/badge/Control%20%26%20Audit-Fabric%20SQL%20Database-4C6487?style=flat-square&amp;labelColor=354D6D" />
  <img alt="Orchestration Plane: Fabric Data Pipelines" src="https://img.shields.io/badge/Orchestration-Fabric%20Data%20Pipelines-5B4B91?style=flat-square&amp;labelColor=40336D" />
  <img alt="Data Plane: Fabric Lakehouse" src="https://img.shields.io/badge/Data-Fabric%20Lakehouse-397E78?style=flat-square&amp;labelColor=265C57" />
</p>

<p align="center">
  <a href="#architecture">Architecture</a> ·
  <a href="#design-highlights">Design highlights</a> ·
  <a href="#how-the-framework-works">How it works</a> ·
  <a href="#start-here">Start here</a> ·
  <a href="#run-the-example">Run the example</a>
</p>

Separate pipelines work well for a few source objects, but repeating the same load logic across many objects becomes harder to maintain.

This repository implements a **metadata-driven ingestion framework in Microsoft Fabric**. Instead of maintaining
separate pipelines for individual source objects, the framework uses configuration tables to define what to ingest,
how to process it, and where to write the results. Reusable orchestration routes each object through the appropriate
ingestion path, with consistent watermark management and run auditing.

The repository demonstrates the framework with end-to-end **batch ingestion examples** for SQL Server tables and CSV
files from SFTP. Both paths support FULL and INCREMENTAL loads into **Bronze Delta tables in a Fabric Lakehouse**.

## Architecture

![Metadata-driven ingestion architecture in Microsoft Fabric. Fabric SQL Database holds source configuration, logical
connection references, incremental state, and object-run audits; orchestration routes requests to SQL Server and SFTP
adapters that write to Lakehouse Bronze Delta.](docs/assets/architecture-overview.svg)

Fabric SQL Database holds source configurations, logical source/target connection references, incremental state
(**committed watermarks**), and terminal object-run audits. Each **source object** is a configured ingestion unit:
a SQL Server table or a logical SFTP file feed that may match multiple physical files. Fabric Data Pipelines use
this metadata to select ingestion paths and coordinate loading into Bronze Delta tables.

See [Architecture & Design Decisions](docs/architecture/framework-overview.md) for the pipeline structure and design trade-offs.

## Design highlights

- **Reusable, metadata-driven orchestration.** Configure source objects, connections, load strategies, and Bronze targets without building a separate pipeline for each dataset.
- **Safe incremental checkpoints.** Only eligible successful REGULAR incremental runs advance watermarks; BACKFILL and no-new-data SKIPPED leave them unchanged.
- **Scoped failure recovery.** Failed Bronze writes trigger cleanup limited to the affected object execution. For incremental runs, uncertain completion results are checked before removing data.
- **Operational monitoring.** Fabric Monitor tracks pipeline runs; SQL audit tables store object-level results, and a Power BI dashboard makes statuses, counts, and errors easier to review.

**Implementation scope:** Batch ingestion from SQL Server tables and CSV files delivered over SFTP. Other relational
database connectors, Parquet/JSON file readers, and API-based batch ingestion are not implemented.

## How the framework works

| Stage | What happens |
| --- | --- |
| **Configure** | Define source details, connection references, load strategies, and Bronze targets through shared metadata. |
| **Select and route** | Gather active configurations (optionally filtered by source system) or use an explicit request list. Validate and route each object to the right ingestion path. |
| **Load Bronze** | Copy SQL Server table data directly into Bronze Delta tables. For SFTP, land the raw files first, then parse and append their records to Bronze Delta tables. |
| **Finalize and inspect** | Save each object's final status and counts in SQL audit tables, and update eligible incremental checkpoints. Review pipeline execution in Fabric Monitor and audit summaries in Power BI. |

## Start here

You do **not** need a Fabric workspace to review the architecture and code. Choose a route rather than reading every document in order:

| Your goal | Recommended entry |
| --- | --- |
| **Get the design in one pass** | [Architecture & Design Decisions](docs/architecture/framework-overview.md) — orchestration, state, and trade-offs |
| **Understand how it works in code** | [Technical Learning Path](docs/guides/learning-path.md) — guided SQL Server/SFTP walkthroughs, then deeper references |
| **Rebuild a working DEV demo** | [Environment Rebuild](docs/operations/environment-rebuild.md) — new-workspace checklist, with the [SQL run order](scripts/RUN_ORDER.md) |
| **Check what was actually tested** | [DEV Evidence & Benchmark Plan](docs/benchmarks/evidence-and-test-plan.md) — observations versus outstanding validation |

The learning path also indexes the focused guides for Control Plane, pipeline routing, incremental processing, Copy tuning, failure recovery, and monitoring.

**Repository layout:** `fabric/` tracks Fabric Pipeline, Notebook, SQL Database, Lakehouse, Variable Library, and
Power BI definitions; `scripts/` contains SQL setup and demo fixtures; `infra/` is the optional EC2/Docker Compose
source environment. Git-tracked definitions are not a backup of Bronze rows, audit history, watermarks, or
credentials.

## Run the example

To reproduce the examples, follow the [workspace setup guide](docs/operations/environment-rebuild.md) and
[SQL and sample-data setup sequence](scripts/RUN_ORDER.md). These instructions are intended for a new, empty DEV
workspace and should not be used to overwrite an existing environment.

Once the sources and Fabric items are configured, run `pl_ingest_orchestrator`. For example, to select the active SFTP source objects:

```text
p_run_requests = []
p_source_system = "LOGISTICS_VENDOR"
```

The orchestrator selects matching objects and invokes the required child pipelines. After the run, inspect its
activities in **Fabric Monitor**, then check `audit.ingestion_log` and the **Power BI Operations Report** for
recorded results. The [SFTP walkthrough](docs/guides/sftp-file-ingestion.md) shows how to compare Landing, Bronze,
and watermark state.

To set up the optional SQL Server and SFTP demo environment, see the
[EC2/Docker Compose setup](infra/source/README.md). This environment is not required to explore the repository;
review its configuration and security notes before deploying it.

## License

No license is currently included. Public access does not by itself grant reuse or redistribution rights.
