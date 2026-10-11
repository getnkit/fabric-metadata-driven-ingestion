CREATE OR ALTER VIEW audit.v_monitor_latest_source
AS
WITH ranked_batches AS
(
    SELECT
        b.*,
        ROW_NUMBER() OVER
        (
            PARTITION BY b.source_system
            ORDER BY b.batch_end_time DESC, b.batch_id DESC
        ) AS recency_rank
    FROM audit.v_monitor_source_batch AS b
)
SELECT
    source_system,
    batch_id,
    object_count,
    success_count,
    failed_count,
    skipped_count,
    warn_count,
    cancelled_count,
    source_rows,
    target_rows,
    batch_start_time,
    batch_end_time,
    CASE
        WHEN failed_count > 0 THEN 'FAILED'
        WHEN cancelled_count > 0 THEN 'CANCELLED'
        WHEN warn_count > 0 THEN 'WARN'
        WHEN success_count > 0 THEN 'SUCCESS'
        ELSE 'SKIPPED'
    END AS source_status
FROM ranked_batches
WHERE recency_rank = 1;
