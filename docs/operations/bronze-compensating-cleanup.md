# Bronze Compensating Cleanup

This runbook documents the framework's automatic compensating cleanup for append-oriented Bronze ingestion.

## Why it exists

A Bronze write and the control/audit finalization are not one distributed transaction. A pipeline can fail after rows have already reached Bronze while the watermark/control state remains uncommitted. A blind rerun can then append the same logical input again.

The recovery scope is the ingestion `batch_id`.

## Reusable component

The framework uses one notebook item:

```text
nb_cleanup_bronze_batch_rows
```

Inputs:

```text
p_workspace_id
p_lakehouse_id
p_target_schema
p_target_table
p_batch_id
```

The notebook resolves the target Delta table, counts rows for the supplied `_batch_id`, deletes only those rows, re-counts the same batch, and fails with `BRONZE_CLEANUP_INCOMPLETE` if any rows remain.

The notebook is idempotent: a retry against an already-clean batch succeeds with zero rows removed.

## Automatic trigger contexts

Current active append paths use the same notebook in two failure contexts:

```text
nb_cleanup_bronze_write_failed
= a Bronze write activity or Bronze-writing notebook failed and may have left partial rows

nb_cleanup_bronze_post_write_failed
= Bronze write succeeded, but a later control step failed before successful finalization
```

The same cleanup notebook logical item is reused; only the calling activity name describes the failure boundary.

## Success and failure behavior

If cleanup succeeds, the original ingestion failure is finalized with watermark advancement disabled.

If cleanup fails, the run is finalized as FAILED with `BRONZE_CLEANUP_FAILED`, and the pipeline fails explicitly. Do not rerun blindly until the failed batch has been reconciled.

## Safety boundary

Do not automatically delete Bronze rows after `sp_finalize_success` itself fails.

That stored procedure may have committed the audit/watermark transaction before the client observed the failure. Automatically deleting Bronze after an ambiguous successful finalization could leave committed control state pointing past missing data.

## Verification queries

Audit:

```sql
SELECT TOP 5
    ingestion_log_id,
    ingestion_config_id,
    batch_id,
    pipeline_run_id,
    status,
    processing_lower_bound,
    processing_upper_bound,
    source_row_count,
    target_row_count,
    error_code,
    error_message
FROM audit.ingestion_log
WHERE ingestion_config_id = <config_id>
ORDER BY ingestion_log_id DESC;
```

Watermark:

```sql
SELECT
    ingestion_config_id,
    watermark_field,
    last_watermark_value,
    last_successful_batch_id,
    last_successful_pipeline_run_id
FROM control.pipeline_watermarks
WHERE ingestion_config_id = <config_id>;
```

Bronze batch check:

```sql
SELECT COUNT(*) AS batch_rows
FROM <target_schema>.<target_table>
WHERE _batch_id = '<batch_id>';
```

For a failed run that completed automatic cleanup, `batch_rows` must be zero and the watermark must remain at the previously committed value.

## Manual fallback

If an operational incident predates the automatic cleanup path, or cleanup itself could not run, reconcile only the failed `_batch_id` using a Fabric Notebook / Spark Delta operation and verify zero remaining rows before rerun.
