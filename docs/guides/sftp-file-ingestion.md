# SFTP File Ingestion Guide

This guide follows the existing `LOGISTICS_VENDOR` demo through its control metadata, Fabric pipelines, Lakehouse Landing and Bronze, and SQL audit. The point is to understand how one pipeline framework handles two file workloads without building a separate orchestration tree for each file.

You can read the artifacts without running Fabric. The optional verification queries require an already configured DEV environment. If you are setting up a new workspace, complete the [environment rebuild guide](../operations/environment-rebuild.md) first.

## What you will learn

By the end, you should be able to explain:

- How an ingestion configuration identifies a source, target, and loading strategy.
- How the same orchestrator dispatches a FULL file snapshot and an INCREMENTAL file feed.
- Why SFTP files are copied to Lakehouse Files before the Notebook writes Bronze Delta.
- Where to inspect a run's terminal status, record counts, and watermark.

The canonical execution entry point is `pl_ingest_orchestrator`. Do not start a child adapter directly.

## 1. Start with two source objects

The DEV metadata seed defines two active objects for the `LOGISTICS_VENDOR` source system:

| Source object | Source file selection | Load strategy | Bronze target |
| --- | --- | --- | --- |
| `inventory_snapshot` | `inventory_snapshot.csv` | FULL | `fulfillment.inventory_snapshots` |
| `inventory_movement` | `inventory_movement_*.csv` | INCREMENTAL | `fulfillment.inventory_movements` |

The snapshot represents current inventory. The movement files represent separate change events delivered over time. Both are delimited text, but their processing boundaries differ.

Read the seed statements in [04_seed_ingestion_metadata.sql](../../scripts/control/04_seed_ingestion_metadata.sql). Inspect the [snapshot fixture](../../scripts/source/sftp/outbound/inventory/inventory_snapshot.csv) and the [SFTP sample directory](../../scripts/source/sftp/outbound/inventory/) to see the actual source layouts.

**Inspect the Control Plane.** In the Fabric SQL Database `sqldb_ingestion_control`, run this read-only query:

```sql
SELECT
    ingestion_config_id,
    source_system,
    source_object,
    ingestion_pattern,
    file_format,
    source_path,
    landing_path,
    target_schema,
    target_table,
    load_strategy,
    watermark_field,
    is_active
FROM control.ingestion_config
WHERE source_system = 'LOGISTICS_VENDOR'
ORDER BY source_object;
```

Look for three important differences:

1. `inventory_snapshot` uses `FULL` and has no watermark field.
2. `inventory_movement` uses `INCREMENTAL` with `last_modified_time`.
3. Both objects share the FILE routing path and use a Files-relative `landing_path` that begins with `landing/`, not `Files/landing/`.

The parser options are stored in `source_options`, including `file_name_pattern`, `delimiter`, `has_header`, `encoding`, `quote`, and `escape`. The FILE Router currently supports `DELIMITED_TEXT` only. A schema column may permit other format names without implying that their readers are implemented.

**Why this matters:** adding another supported file object is principally a metadata and source-onboarding task. It should not require copying the entire orchestration tree.

## 2. Choose the run scope at the orchestrator

Open `fabric/pl_ingest_orchestrator.DataPipeline/pipeline-content.json` and find the pipeline parameters. To run only the two active Logistics configurations, use:

```text
p_run_requests = []
p_source_system = "LOGISTICS_VENDOR"
```

An empty request array asks the framework to select active configurations. The nonblank source-system parameter narrows that selection. With both parameters empty, the same orchestrator selects all active configurations.

The top-level activities first establish the batch ID, check the required runtime bindings, and reject ambiguous scope. The source-system path then invokes `pl_ingest_config_paginator`. The paginator selects active configurations before the Dispatcher invokes object controllers.

The relevant routing sequence is:

```text
pl_ingest_orchestrator
  -> pl_ingest_config_paginator
  -> pl_ingest_config_dispatcher
  -> pl_ingest_object_controller
  -> pl_ingest_file_router
       -> pl_ingest_sftp_full_adapter
       -> pl_ingest_sftp_incremental_adapter
```

The FILE Router checks the file format before choosing an adapter. Its `if_supported_file_format` activity evaluates the requested format against `DELIMITED_TEXT`; its `sw_file_route` activity uses connection type and load strategy to choose the path.

Read the [request contract](../operations/run-request-examples.md) for explicit `config_id` requests and BACKFILL examples. A nonempty `p_run_requests` together with a nonblank `p_source_system` is deliberately rejected as `AMBIGUOUS_RUN_SCOPE`.

## 3. Follow the FULL snapshot through Landing

Open `fabric/pl_ingest_sftp_full_adapter.DataPipeline/pipeline-content.json` and inspect these activities in order:

1. `set_landing_relative_path` builds a path for this object execution.
2. `copy_sftp_to_landing` uses Binary Copy to preserve the delivered source file.
3. `if_landing_file_count_consistent` compares the files read and written by the Copy activity.
4. `nb_load_file_landing_to_bronze` parses the landed file and appends Bronze Delta rows.
5. `sp_finalize_success` writes the successful terminal audit result.

A physical Landing directory includes the ingestion date, configuration ID, batch ID, and object pipeline run ID:

```text
Files/landing/logistics_vendor/inventory_snapshot/
  ingestion_date=YYYY-MM-DD/
    ingestion_config_id=<config_id>/
      batch_id=<batch_id>/
        pipeline_run_id=<object_run_id>/
```

This path is execution-scoped so a later run does not overwrite an earlier run's Landing files. The configured `landing_path` itself is relative to the Lakehouse Files root. The adapter and Notebook add the necessary runtime path segments.

The copy stage is Binary because source preservation and CSV parsing are separate responsibilities. The Notebook performs parsing only after the raw file has arrived in Landing.

The FULL snapshot does not have a persistent watermark. Repeating a successful FULL run appends a new Bronze batch; it does not replace the previous successful batch. See [FILE ingestion design](../architecture/file-ingestion-design.md) for the file count check and cleanup behavior.

## 4. Compare the INCREMENTAL movement feed

The `inventory_movement` configuration uses the same routing machinery but selects `pl_ingest_sftp_incremental_adapter`. Its `last_modified_time` checkpoint is maintained in `control.pipeline_watermarks`.

Inspect the checkpoint with this read-only query:

```sql
SELECT
    c.ingestion_config_id,
    c.source_object,
    w.watermark_field,
    w.last_watermark_value,
    w.last_successful_batch_id,
    w.last_successful_pipeline_run_id,
    w.watermark_updated_at
FROM control.ingestion_config AS c
JOIN control.pipeline_watermarks AS w
  ON w.ingestion_config_id = c.ingestion_config_id
WHERE c.source_system = 'LOGISTICS_VENDOR'
ORDER BY c.source_object;
```

For a normal incremental file run, the committed watermark supplies the lower bound and the run start time supplies the upper bound. The SFTP file selection uses the remote **Last Modified** timestamp. It does not use a timestamp inside the CSV payload.

If the scan finds no matching files, the run is `SKIPPED` and the checkpoint does not advance. A successful REGULAR incremental run with matching files can advance the watermark through guarded SQL finalization. An explicitly requested BACKFILL uses supplied historical bounds and does not move the operational checkpoint.

The full boundary rules are recorded in [Generic Incremental Watermark](../architecture/generic-incremental-watermark.md). Do not infer file ingestion from the payload's business event date.

## 5. Verify the terminal object audits

After an actual DEV run, use this read-only query to inspect the most recent object outcomes:

```sql
SELECT TOP (20)
    batch_id,
    pipeline_run_id,
    source_system,
    source_object,
    run_type,
    load_strategy,
    status,
    processing_lower_bound,
    processing_upper_bound,
    source_row_count,
    target_row_count,
    error_code,
    end_time
FROM audit.ingestion_log
WHERE source_system = 'LOGISTICS_VENDOR'
ORDER BY ingestion_log_id DESC;
```

Check that each object has its own terminal audit, and use `batch_id` to correlate objects belonging to the same orchestrated batch. Do not assume every run will produce `SUCCESS`. An unchanged incremental feed may produce `SKIPPED`; failures must be investigated rather than treated as successful ingestion.

For an actual success, compare the audit's target, counts, and run identifiers with the corresponding Bronze table and technical metadata. The FILE Notebook supplies its processed-row metric after a successful write; that count is not an independent second Bronze recount.

The [Power BI monitoring report](../operations/monitoring-report.md) summarizes persisted object audits. It cannot show master runs that fail before an object audit is written, or every in-progress activity. Use Fabric Monitor for those cases.

## 6. Explain the failure boundary

A single Delta write has transaction atomicity. The pipeline as a whole does not have one distributed transaction spanning Lakehouse Delta and Fabric SQL Database.

For a failed or uncertain Bronze write, the framework has an execution-scoped cleanup path. That path identifies rows by the combination of `_batch_id` and `_pipeline_run_id` and avoids deleting successful rows from another object sharing the same batch ID. An ambiguous success-finalization failure needs reconciliation before any compensation decision.

Study [Bronze Compensating Cleanup](../operations/bronze-compensating-cleanup.md) and [Retry, Rerun, and Backfill](../operations/retry-rerun-backfill.md) for the detailed behavior.

## Try explaining it back

- Why do the snapshot and movement feed use the same Object Controller but different SFTP adapters?
- Which timestamp determines whether a movement file is new?
- What would be incorrect about advancing the watermark before Bronze has committed?
- Why does an append-only successful BACKFILL not guarantee that a downstream business table contains no duplicate business keys?

The next step is to follow the [complete technical learning path](learning-path.md), which covers SQL Server Copy, optimistic finalization, recovery, and monitoring in more detail.

**About the examples:** this guide documents definitions and expected framework behavior. Screenshots of individual runs will be added only after the matching DEV scenario has been executed and verified. It does not claim to demonstrate an independently repeated run inside this document.
