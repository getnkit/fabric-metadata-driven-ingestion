# Pipeline Activity Naming Standard

Microsoft defines syntax and length rules for activity names, but does not
prescribe a semantic naming convention for Fail or Stored Procedure activities.
This project therefore uses a readable project convention. Activity-type prefixes are explicit where practical; Copy uses `copy_` rather than an abbreviation.

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
| Stored Procedure | `sp_` |
| Fail | `fail_` |

## Finalization

Successful terminal states use:

```text
sp_finalize_success
sp_finalize_skipped
```

For Copy failures, identify the destination layer rather than spelling out the
entire source-to-target path:

```text
sp_finalize_<target>_copy_failed
fail_<target>_copy
fail_<target>_copy_finalization
```

Examples:

```text
sp_finalize_landing_copy_failed
fail_landing_copy
fail_landing_copy_finalization

sp_finalize_bronze_copy_failed
fail_bronze_copy
fail_bronze_copy_finalization
```

This stays short while distinguishing pipelines that contain more than one Copy
activity.

For non-Copy failures, use the operation name:

```text
sp_finalize_source_query_failed
fail_source_query
fail_source_query_finalization
```

The Fail activity error codes remain semantic and stable across connectors:

```text
COPY_FAILED
SOURCE_QUERY_FAILED
FINALIZATION_FAILED
```

## Legacy exception

`pl_ingest_full_legacy` is retained as a reference artifact and is not
refactored to this convention. New and active pipelines follow this standard.


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
```

Current incremental worker examples:

```text
pl_load_azure_sql_incremental
pl_load_sftp_incremental
```

The `load` verb is preferred over `process` for these workers because their responsibility is ingestion data movement into Landing/Bronze, not downstream transformation. Granularity suffixes such as `_file` or `_object` are omitted unless they become necessary to distinguish multiple workers with otherwise identical names.
