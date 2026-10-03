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

Physical Fabric Copy activities keep the `copy_` prefix. Failure/recovery activities describe the data-layer effect rather than the implementation primitive, so target mutation failures use `write` / `post_write`.

## Finalization

Successful terminal states use:

```text
sp_finalize_success
sp_finalize_skipped
```

For target-write failures:

```text
sp_finalize_<target>_write_failed
fail_<target>_write
fail_<target>_write_finalization
```

Examples:

```text
sp_finalize_landing_write_failed
fail_landing_write
fail_landing_write_finalization

sp_finalize_bronze_write_failed
fail_bronze_write
fail_bronze_write_finalization
```

For non-write failures, use the failing operation/stage name:

```text
sp_finalize_source_query_failed
fail_source_query
fail_source_query_finalization
```

## Bronze compensating cleanup

The reusable notebook item is:

```text
nb_cleanup_bronze_batch_rows
```

It deletes Bronze rows for exactly one `_batch_id` and verifies that no rows for that batch remain.

Notebook activity names identify why cleanup was invoked:

```text
nb_cleanup_bronze_write_failed
nb_cleanup_bronze_post_write_failed
```

The distinction is intentional:

```text
write_failed
= the Bronze write activity itself failed and may have left partial rows

post_write_failed
= the Bronze write succeeded, but a later control step failed before successful finalization
```

Cleanup-failure branches retain the same context:

```text
sp_finalize_bronze_write_cleanup_failed
fail_bronze_write_cleanup
fail_bronze_write_cleanup_finalization

sp_finalize_bronze_post_write_cleanup_failed
fail_bronze_post_write_cleanup
fail_bronze_post_write_cleanup_finalization
```

Audit/error codes mirror the semantic failure boundary:

```text
LANDING_WRITE_FAILED
BRONZE_WRITE_FAILED
BRONZE_POST_WRITE_FAILED
BRONZE_CLEANUP_FAILED
FINALIZATION_FAILED
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

Pipeline names distinguish orchestration from the worker that performs the data load:

```text
pl_master_ingestion
= top-level framework entry point

pl_ingest_<pattern>_<strategy>
= pattern-level ingestion routing/orchestration

pl_ingest_<connector>_<strategy>
= connector-level ingestion orchestration

pl_load_<connector>_<strategy>
= worker used only when a separate physical load stage is justified

pl_ingest_config_page
= bounded metadata-page worker used to keep Lookup enumeration below platform limits
```

Current incremental worker example:

```text
pl_load_azure_sql_incremental
```

SFTP incremental stays inside `pl_ingest_sftp_incremental` because the native SFTP Copy activity can recursively land the complete candidate file set in one activity; a separate scanner/loader pipeline would add orchestration without adding a real connector boundary.

Invoke Pipeline activity names mirror the called pipeline name without the `pl_` prefix:

```text
pl_ingest_database_incremental -> inv_ingest_database_incremental
pl_ingest_azure_sql_incremental -> inv_ingest_azure_sql_incremental
pl_load_azure_sql_incremental -> inv_load_azure_sql_incremental
pl_ingest_sftp_incremental -> inv_ingest_sftp_incremental
pl_ingest_config_page -> inv_ingest_config_page
```

The `load` verb is preferred over `process` when a separate worker is needed because its responsibility is ingestion data movement, not downstream transformation. Do not create a worker pipeline solely to break up a flow that a native connector activity can already perform cleanly.
