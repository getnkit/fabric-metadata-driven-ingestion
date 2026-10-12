CREATE VIEW audit.v_monitor_source_batch
AS
SELECT
    COALESCE(NULLIF(LTRIM(RTRIM(a.source_system)), N''), N'UNKNOWN') AS source_system,
    CAST(a.batch_id AS NVARCHAR(36)) AS batch_id,
    COUNT_BIG(*) AS object_count,
    SUM(CASE WHEN a.status = 'SUCCESS' THEN 1 ELSE 0 END) AS success_count,
    SUM(CASE WHEN a.status = 'FAILED' THEN 1 ELSE 0 END) AS failed_count,
    SUM(CASE WHEN a.status = 'SKIPPED' THEN 1 ELSE 0 END) AS skipped_count,
    CASE
        WHEN MAX(CASE WHEN a.status = 'FAILED' THEN 1 ELSE 0 END) = 1 THEN 'FAILED'
        WHEN MAX(CASE WHEN a.status = 'CANCELLED' THEN 1 ELSE 0 END) = 1 THEN 'CANCELLED'
        WHEN MAX(CASE WHEN a.status = 'WARN' THEN 1 ELSE 0 END) = 1 THEN 'WARN'
        WHEN MAX(CASE WHEN a.status = 'SUCCESS' THEN 1 ELSE 0 END) = 1 THEN 'SUCCESS'
        ELSE 'SKIPPED'
    END AS source_status,
    SUM(COALESCE(a.source_row_count, 0)) AS source_rows,
    SUM(COALESCE(a.target_row_count, 0)) AS target_rows,
    MIN(a.start_time) AS batch_start_time,
    MAX(a.end_time) AS batch_end_time
FROM audit.ingestion_log AS a
GROUP BY
    COALESCE(NULLIF(LTRIM(RTRIM(a.source_system)), N''), N'UNKNOWN'),
    a.batch_id;
