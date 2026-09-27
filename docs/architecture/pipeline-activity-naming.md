# Pipeline Activity Naming Standard

This document defines the naming convention for Fabric Data Factory pipeline
activities in the active ingestion framework.

## Prefixes

| Activity type | Prefix |
|---|---|
| Copy | `cpy_` |
| Lookup | `lkp_` |
| Set Variable | `set_` |
| If Condition | `if_` |
| Switch | `sw_` |
| Invoke Pipeline | `inv_` |
| Stored Procedure | `sp_` |
| Fail | `fail_` |

## Finalization activities

All ingestion audit finalization activities call
`[control].[usp_finalize_ingestion_run]`.

Use outcome-oriented names for terminal non-error states:

```text
sp_finalize_success
sp_finalize_skipped
```

For an execution-stage failure, name the stored-procedure activity after the
failed operation:

```text
sp_finalize_<operation>_failed
```

Examples:

```text
sp_finalize_source_query_failed
sp_finalize_source_to_bronze_copy_failed
sp_finalize_sftp_to_landing_copy_failed
sp_finalize_landing_to_bronze_copy_failed
```

Do not include load strategy or connector family in the finalization name when
the failed operation already identifies the stage.

## Fail activities

After failure audit finalization succeeds, propagate the original operation
failure with:

```text
fail_<operation>
```

If failure audit finalization itself fails, use:

```text
fail_<operation>_finalization
```

Examples:

```text
fail_source_query
fail_source_query_finalization

fail_source_to_bronze_copy
fail_source_to_bronze_copy_finalization

fail_sftp_to_landing_copy
fail_sftp_to_landing_copy_finalization

fail_landing_to_bronze_copy
fail_landing_to_bronze_copy_finalization
```

The Fail activity's `errorCode` remains semantic and stable across connectors:

```text
COPY_FAILED
SOURCE_QUERY_FAILED
FINALIZATION_FAILED
```

## Legacy exception

`pl_ingest_full_legacy` is retained as a reference artifact and is not
refactored to this convention. New or active pipelines must follow this
standard.
