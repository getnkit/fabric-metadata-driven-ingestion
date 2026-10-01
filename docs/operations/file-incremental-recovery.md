# FILE Incremental Recovery

This runbook covers the failure boundary where a FILE incremental run writes rows to Bronze successfully but fails before the run is finalized and the watermark is advanced.

## Why this matters

The Bronze write and the control/audit finalization are not one distributed transaction. A run can therefore fail after data is already present in Bronze. Because the watermark is intentionally not advanced for a failed run, a blind REGULAR rerun can rediscover the same file and append duplicate Bronze rows.

## Recovery rule

Do not blindly rerun a failed FILE incremental batch when file processing may already have started.

1. Identify the failed batch in `audit.ingestion_log` and keep the FAILED audit record unchanged.
2. Check Bronze for rows with that failed `_batch_id`.
3. Because the Lakehouse SQL analytics endpoint can lag behind the Delta write, wait and re-query before concluding that the batch has zero Bronze rows.
4. If the failed batch has Bronze rows, remove only that failed batch from Bronze using Spark/Notebook Delta DML.
5. Verify the failed batch now has zero Bronze rows.
6. Confirm `control.pipeline_watermarks.last_watermark_value` and the last-successful references still point to the last successful run.
7. Rerun the ingestion request.
8. Validate the new SUCCESS audit row, row counts, resolved `landing_path`, Bronze row count, and watermark advancement.

## Example checks

Audit:

```sql
SELECT TOP 5
    ingestion_log_id,
    ingestion_config_id,
    batch_id,
    pipeline_run_id,
    status,
    landing_path,
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
SELECT
    _batch_id,
    _pipeline_run_id,
    COUNT(*) AS row_count
FROM <target_schema>.<target_table>
WHERE _batch_id = '<failed_batch_id>'
GROUP BY _batch_id, _pipeline_run_id;
```

If cleanup is required, run the following from a Fabric Notebook / Spark SQL context against the Delta table:

```sql
DELETE FROM <target_schema>.<target_table>
WHERE _batch_id = '<failed_batch_id>';
```

## Current framework boundary

This is an explicit operational recovery path, not automatic deduplication. The framework keeps Bronze append-oriented and avoids introducing MERGE/deduplication semantics into raw ingestion solely to handle a rare post-write control-plane failure.

Automatic recovery can be added later if the framework needs unattended recovery from this boundary. Until then, the failed `batch_id` is the recovery scope and must be reconciled before rerun.
