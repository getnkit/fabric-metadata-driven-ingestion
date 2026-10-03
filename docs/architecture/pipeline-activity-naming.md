# Pipeline Activity Naming Standard

Microsoft defines syntax and length rules for activity names, but does not prescribe a semantic naming convention for pipeline activities. This project therefore uses a readable project convention.

## Prefixes

| Activity type | Prefix |
|---|---|
| Copy | `copy_` |
| Lookup | `lkp_` |
| Get Metadata | `gm_` |
| Filter | `flt_` |
| ForEach | `fe_` |
| Set Variable | `set_` |
| Append Variable | `append_` |
| If Condition | `if_` |
| Switch | `sw_` |
| Invoke Pipeline | `inv_` |
| Notebook | `nb_` |
| Stored Procedure | `sp_` |
| Fail | `fail_` |

Set Variable activity names mirror the variable they set, dropping the variable's `v_` prefix:

```text
v_run_type -> set_run_type
v_lower_bound -> set_lower_bound
```

Physical Fabric Copy activities keep the `copy_` prefix. Failure/recovery activities describe the data-layer effect rather than the implementation primitive, so target mutation failures use `write` / `post_write`.

## Finalization

Expected object-level terminal outcomes use a single audit policy: once an ingestion configuration has been resolved and the run has a batch/config identity, semantic terminal outcomes are finalized to the ingestion audit as `SUCCESS`, `SKIPPED`, or `FAILED` before the pipeline terminates. Framework-level request validation that occurs before an ingestion object/configuration is resolved may fail without creating an ingestion audit record.

Successful terminal states use:

```text
sp_finalize_success
sp_finalize_skipped
```

For expected failure outcomes, the finalization stored procedure records the `FAILED` audit first. A semantic Fail activity runs only after that stored procedure succeeds:

```text
sp_finalize_<failure>
fail_<failure>
```

If a finalization stored procedure itself fails, let that activity failure propagate naturally. Do not add a second `fail_*_finalization` wrapper: it cannot recover or persist the missing audit and only adds orchestration ceremony.

For target-write failures:

```text
sp_finalize_<target>_write_failed
fail_<target>_write
```

Examples:

```text
sp_finalize_landing_write_failed
fail_landing_write

sp_finalize_bronze_write_failed
fail_bronze_write
```

For non-write failures, use the failing operation/stage name:

```text
sp_finalize_source_query_failed
fail_source_query
```

Unexpected framework/runtime faults in lightweight control activities may bubble naturally when no meaningful recovery or compensating action is added. Do not create a dedicated Stored Procedure + Fail branch around every Set Variable or expression solely for audit completeness.

## Bronze compensating cleanup

The reusable notebook item is:

```text
nb_cleanup_bronze_batch_rows
```

It deletes Bronze rows for exactly one `_batch_id` and verifies that no rows for that batch remain.

The active automatic-cleanup activity name is:

```text
nb_cleanup_bronze_write_failed
```

`write_failed` means the Bronze write activity itself failed and may have left
partial rows. Control-only decisions that can be evaluated before the write stay
before the Bronze mutation boundary; failures there are finalized without Delta
cleanup.

Cleanup-failure branches retain the write context:

```text
sp_finalize_bronze_write_cleanup_failed
fail_bronze_write_cleanup
```

Audit/error codes mirror the semantic failure boundary:

```text
LANDING_WRITE_FAILED
BRONZE_WRITE_FAILED
BRONZE_POST_WRITE_FAILED
BRONZE_CLEANUP_FAILED
```

## Pipeline vs Notebook Boundary

Use Data Factory pipeline activities for orchestration, connector-native movement, metadata lookup, validation, routing, and audit/finalization.

Use a Notebook when the responsibility is a reusable Spark/Delta data operation that would otherwise require duplicated format-specific or stateful pipeline mechanics.

Current reusable notebooks:

```text
nb_cleanup_bronze_batch_rows
= idempotent Delta cleanup scoped by _batch_id

nb_load_landing_to_bronze
= batch-scoped recursive Landing parse + technical metadata + Bronze Delta append
```

Do not replace a simple connector-native Copy activity with a Notebook just to make the implementation uniform. In particular, relational DATABASE -> Bronze ingestion remains a Copy activity because Fabric already provides the required source connector, filtering, row movement, and monitoring without introducing Spark compute or source-driver/authentication logic into a Notebook.

## Safety boundary

Automatic Bronze cleanup is used only when the framework knows the control-state commit has not succeeded.

Do not automatically delete Bronze rows after `sp_finalize_success` itself fails. That stored procedure may have committed the audit/watermark transaction before the client observed the failure; deleting Bronze after an ambiguous successful finalization could create data loss.

## Legacy exception

`pl_ingest_full_legacy` is retained as a reference artifact and is not refactored to this convention. New and active pipelines follow this standard.

## Pipeline names

Active ingestion pipelines use the `pl_ingest_` workload namespace so that ingestion items remain identifiable when the workspace later contains transformation, data-quality, or maintenance pipelines.

The naming shape is role-oriented:

```text
pl_ingest_<scope>_<role>
```

The role suffix communicates the pipeline's responsibility in the ingestion hierarchy:

| Role | Responsibility |
|---|---|
| `orchestrator` | Top-level ingestion framework entry point; establishes run scope and coordinates config-page execution. |
| `dispatcher` | Enumerates and dispatches a bounded page of ingestion configurations. |
| `controller` | Owns the lifecycle of one resolved ingestion object/configuration, including validation and route selection. |
| `router` | Selects the connector-specific implementation for a generic ingestion pattern such as DATABASE/FULL or FILE/INCREMENTAL. |
| `adapter` | Converts generic ingestion metadata into connector-specific configuration **and executes the connector-specific ingestion flow**. It is not only a metadata translator. |
| `loader` | Optional physical load sub-step split from an adapter only when a separate execution boundary is technically justified. |

Current active hierarchy:

```text
pl_ingest_orchestrator
  -> pl_ingest_config_page_dispatcher
    -> pl_ingest_object_controller
      -> pl_ingest_database_full_router
        -> pl_ingest_azure_sql_full_adapter
      -> pl_ingest_database_incremental_router
        -> pl_ingest_azure_sql_incremental_adapter
          -> pl_ingest_azure_sql_incremental_loader
      -> pl_ingest_file_full_router
        -> pl_ingest_sftp_full_adapter
      -> pl_ingest_file_incremental_router
        -> pl_ingest_sftp_incremental_adapter
```

`pl_ingest_orchestrator` is the supported external entry point for the ingestion framework. Dispatcher, controller, router, adapter, and loader pipelines are internal implementation pipelines and may rely on framework-level request/page validation performed upstream. Each internal pipeline still validates the metadata, state, connector capability, or data-mutation boundary that it owns.

Platform Retry/Rerun is treated as execution recovery and is not encoded as a framework `run_type`. Direct manual reruns of internal child pipelines are not part of the supported operational contract; recovery enters through the top-level orchestrator.

`config_page` is deliberate terminology: the dispatcher reads a deterministic SQL page of configuration IDs using `ORDER BY ... OFFSET ... FETCH NEXT ...`, keeping each Lookup result within the platform row limit. `page` is kept distinct from the framework's ingestion `batch_id`, which represents execution/correlation rather than metadata pagination.

Invoke Pipeline activity names mirror the called pipeline name without the `pl_` prefix:

```text
pl_ingest_config_page_dispatcher          -> inv_ingest_config_page_dispatcher
pl_ingest_object_controller               -> inv_ingest_object_controller
pl_ingest_database_incremental_router     -> inv_ingest_database_incremental_router
pl_ingest_azure_sql_incremental_adapter   -> inv_ingest_azure_sql_incremental_adapter
pl_ingest_azure_sql_incremental_loader    -> inv_ingest_azure_sql_incremental_loader
pl_ingest_sftp_incremental_adapter        -> inv_ingest_sftp_incremental_adapter
```

Do not add a loader merely for naming symmetry. For example, Azure SQL FULL and the SFTP adapters remain single connector-specific adapter pipelines because their native activity structure does not require the additional pipeline boundary. The Azure SQL incremental loader exists because the adapter needs a separate physical-load execution boundary for its nested branching structure.
