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
| Until | `until_` |
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
nb_cleanup_bronze_file_traversal_failed
```

The distinction is intentional:

```text
write_failed
= the Bronze write activity itself failed and may have left partial rows

post_write_failed
= the Bronze write succeeded, but a later control step failed before successful finalization

file_traversal_failed
= FILE incremental recursive traversal failed after one or more nested-file loads may have written Bronze rows
```

Cleanup-failure branches retain the same context:

```text
sp_finalize_bronze_write_cleanup_failed
fail_bronze_write_cleanup
fail_bronze_write_cleanup_finalization

sp_finalize_bronze_post_write_cleanup_failed
fail_bronze_post_write_cleanup
fail_bronze_post_write_cleanup_finalization

sp_finalize_file_traversal_cleanup_failed
fail_file_traversal_cleanup
fail_file_traversal_cleanup_finalization
```

The original traversal failure branch is:

```text
sp_finalize_file_traversal_failed
fail_file_traversal
fail_file_traversal_finalization
```

Audit/error codes mirror the semantic failure boundary:

```text
LANDING_WRITE_FAILED
BRONZE_WRITE_FAILED
BRONZE_POST_WRITE_FAILED
FILE_TRAVERSAL_FAILED
BRONZE_CLEANUP_FAILED
FINALIZATION_FAILED
```

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
= worker that performs the actual data movement/write for that connector

pl_scan_<connector>_<scope>_<strategy>
= bounded discovery helper used by an orchestration pipeline
```

Current incremental worker examples:

```text
pl_load_azure_sql_incremental
pl_load_sftp_incremental
pl_scan_sftp_folder_incremental
```

Invoke Pipeline activity names mirror the called pipeline name without the `pl_` prefix:

```text
pl_ingest_database_incremental -> inv_ingest_database_incremental
pl_ingest_azure_sql_incremental -> inv_ingest_azure_sql_incremental
pl_load_azure_sql_incremental -> inv_load_azure_sql_incremental
pl_ingest_sftp_incremental -> inv_ingest_sftp_incremental
pl_load_sftp_incremental -> inv_load_sftp_incremental
pl_scan_sftp_folder_incremental -> inv_scan_sftp_folder_incremental
```

The `load` verb is preferred over `process` for workers because their responsibility is ingestion data movement into Landing/Bronze, not downstream transformation. Granularity suffixes such as `_file` or `_object` are omitted unless they become necessary to distinguish multiple workers with otherwise identical names.
