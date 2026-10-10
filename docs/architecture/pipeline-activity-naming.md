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
v_processing_lower_bound -> set_processing_lower_bound
```

When the same logical operation appears in alternative branches, append the branch/execution context consistently rather than naming only one branch specially:

```text
set_processing_upper_bound_regular
set_processing_upper_bound_backfill

copy_source_to_bronze_query_auto
copy_source_to_bronze_query_tuned
copy_source_to_bronze_table_auto
copy_source_to_bronze_table_tuned
```

ForEach activity names should describe the collection being iterated:

```text
fe_run_requests
fe_config_pages
```

Physical Fabric Copy activities keep the `copy_` prefix. Failure/recovery activities describe the data-layer effect rather than the implementation primitive, so target mutation failures use `write` / `post_write`.

## Finalization

Expected object-level terminal outcomes use a single audit policy: once an ingestion configuration has been resolved and the run has a batch/config identity, semantic terminal outcomes are finalized to the ingestion audit as `SUCCESS`, `SKIPPED`, or `FAILED` before the pipeline terminates. Framework-level request validation that occurs before an ingestion object/configuration is resolved may fail without creating an ingestion audit record.

Successful terminal states use:

```text
sp_finalize_success
```

A successful no-data branch may use a more specific success suffix when the pipeline already contains another success finalizer:

```text
sp_finalize_no_new_data_success
```

`SKIPPED` is reserved for work that is intentionally not executed, such as an inactive configuration.

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

The SFTP source-to-Landing `copy_sftp_to_landing` failure is named by its
**Copy operation**, rather than `write`, because the Copy Activity may fail
while reading SFTP, moving data, or writing Lakehouse Files. A failure during
the subsequent Landing cleanup remains a distinct `LANDING_CLEANUP_FAILED`.

```text
nb_cleanup_landing_copy_failed
sp_finalize_landing_copy_failed
fail_landing_copy
sp_finalize_landing_copy_cleanup_failed
fail_landing_copy_cleanup

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

It deletes Bronze rows for exactly one **(`_batch_id`, `_pipeline_run_id`)**
object-execution pair and verifies that no matching rows remain. The batch ID
may be shared by multiple object runs in the same orchestrator execution.

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
LANDING_COPY_FAILED
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

nb_load_file_landing_to_bronze
= batch-scoped recursive Landing parse + technical metadata + Bronze Delta append
```

Do not replace a simple connector-native Copy activity with a Notebook just to make the implementation uniform. In particular, relational DATABASE -> Bronze ingestion remains a Copy activity because Fabric already provides the required source connector, filtering, row movement, and monitoring without introducing Spark compute or source-driver/authentication logic into a Notebook.

## Safety boundary

Automatic Bronze cleanup is used only when the framework knows the control-state commit has not succeeded.

If `sp_finalize_success` fails, `pl_ingest_finalize_success_recovery` first checks the committed audit for the exact object run. Automatic compensating cleanup is allowed **only** when the audit confirms `FAILED / WATERMARK_CONFLICT`; successful or unconfirmed finalization outcomes must not delete Bronze (or Landing). See [Bronze compensating cleanup](../operations/bronze-compensating-cleanup.md) for recovery behavior.

## Pipeline names

Active ingestion pipelines use the `pl_ingest_` workload namespace so that ingestion items remain identifiable when the workspace later contains transformation, data-quality, or maintenance pipelines.

## Batch target invariant

Within this framework, `pl_ingest_*` means batch ingestion orchestrated by
Fabric Data Factory, and its Bronze target type is always Fabric Lakehouse.
Because the destination type is invariant, pipeline names omit destination
suffixes such as `_to_lakehouse_`, and the object-controller route key contains
only the ingestion pattern (`DATABASE`, `FILE`, and future batch patterns).
The controller still validates `target_connection_type = LAKEHOUSE` before
routing. Target connection/schema/table metadata remains required to identify the
actual Lakehouse destination.

The naming shape is role-oriented:

```text
pl_ingest_<scope>_<role>
```

The role suffix communicates the pipeline's responsibility in the ingestion hierarchy:

| Role | Responsibility |
|---|---|
| `orchestrator` | Top-level ingestion framework entry point; establishes run scope and selects Explicit vs All Active execution. |
| `paginator` | Owns ALL ACTIVE metadata counting, page generation, per-page lookup, and sequential page coordination. Zero active configs is a successful no-op. |
| `dispatcher` | Fans out one bounded normalized run-request collection to the per-object controller. |
| `controller` | Owns the lifecycle of one resolved ingestion object/configuration, including validation and route selection. |
| `router` | Selects the connector + load-strategy implementation within a generic ingestion pattern such as DATABASE or FILE. |
| `adapter` | Converts generic ingestion metadata into connector-specific configuration **and executes the connector-specific ingestion flow**. It is not only a metadata translator. |
| `loader` | Optional physical load sub-step split from an adapter only when a separate execution boundary is technically justified. |
| `recovery` | Shared finalization-failure reconciliation and confirmed-conflict cleanup; invoked only after incremental finalization fails. |

Current active hierarchy:

```text
pl_ingest_orchestrator
  ├─ Explicit -> pl_ingest_config_dispatcher
  └─ All Active -> pl_ingest_config_paginator
                    -> pl_ingest_config_dispatcher
                         -> pl_ingest_object_controller
                              -> DATABASE
                                   -> pl_ingest_database_router
                                        -> SQL_SERVER|FULL
                                             -> pl_ingest_sql_server_full_adapter
                                        -> SQL_SERVER|INCREMENTAL
                                             -> pl_ingest_sql_server_incremental_adapter
                                                  -> pl_ingest_sql_server_incremental_loader
                                                       -> (finalize failure) pl_ingest_finalize_success_recovery
                              -> FILE
                                   -> pl_ingest_file_router
                                        -> SFTP|FULL
                                             -> pl_ingest_sftp_full_adapter
                                        -> SFTP|INCREMENTAL
                                             -> pl_ingest_sftp_incremental_adapter
                                                  -> (finalize failure) pl_ingest_finalize_success_recovery
```

`pl_ingest_orchestrator` is the supported external entry point for the ingestion framework. Paginator, dispatcher, controller, router, adapter, loader, and finalize recovery pipelines are internal implementation pipelines and may rely on framework-level request/page validation performed upstream. Each internal pipeline still validates the metadata, state, connector capability, or data-mutation boundary that it owns.

Platform Retry/Rerun is treated as execution recovery and is not encoded as a framework `run_type`. Direct manual reruns of internal child pipelines are not part of the supported operational contract; recovery enters through the top-level orchestrator.

`config_dispatcher` receives one normalized bounded request collection regardless of origin. Explicit requests are passed directly by the Orchestrator. ALL ACTIVE execution is normalized by `pl_ingest_config_paginator`, which queries one deterministic metadata page as REGULAR run-request rows before invoking the same Dispatcher. `page` remains distinct from the ingestion `batch_id`, which represents execution/correlation rather than metadata pagination.

Invoke Pipeline activity names mirror the called pipeline name without the `pl_` prefix by default:

```text
pl_ingest_database_router                 -> inv_ingest_database_router
pl_ingest_sql_server_incremental_adapter   -> inv_ingest_sql_server_incremental_adapter
pl_ingest_sql_server_incremental_loader    -> inv_ingest_sql_server_incremental_loader
pl_ingest_sftp_incremental_adapter         -> inv_ingest_sftp_incremental_adapter
pl_ingest_finalize_success_recovery               -> inv_ingest_finalize_success_recovery
```

When a parent invokes a child only once, use the child-oriented name directly:

```text
pl_ingest_config_dispatcher -> inv_ingest_config_dispatcher
pl_ingest_object_controller -> inv_ingest_object_controller
pl_ingest_config_paginator  -> inv_ingest_config_paginator
```

Add a context suffix only when the same child is invoked more than once inside the same parent and the suffix is needed to distinguish those sibling activities.

Do not add a loader merely for naming symmetry. For example, SQL Server FULL and the SFTP adapters remain single connector-specific adapter pipelines because their native activity structure does not require the additional pipeline boundary. The SQL Server incremental loader exists because the adapter needs a separate physical-load execution boundary for its nested branching structure.
