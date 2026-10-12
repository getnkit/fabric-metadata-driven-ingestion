/*
  DEV: Run in sqldb_ingestion_control after the existing Control/Audit Plane.
  Read-only monitoring views. No changes to audit data, watermarks or pipelines.
  SQL Project definitions in fabric/ are the physical source of truth.
*/
CREATE OR ALTER VIEW audit.v_monitor_source_batch
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
GO

CREATE OR ALTER VIEW audit.v_monitor_latest_source
AS
WITH ranked_batches AS
(
    SELECT b.*,
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
    source_rows,
    target_rows,
    batch_start_time,
    batch_end_time,
    source_status
FROM ranked_batches
WHERE recency_rank = 1;
GO

CREATE OR ALTER VIEW audit.v_monitor_object_history
AS
SELECT
    a.ingestion_log_id,
    COALESCE(NULLIF(LTRIM(RTRIM(a.source_system)), N''), N'UNKNOWN') AS source_system,
    CASE
        WHEN NULLIF(a.source_schema, N'') IS NOT NULL
        THEN CONCAT(a.source_schema, N'.', a.source_object)
        ELSE a.source_object
    END AS source_entity,
    a.ingestion_config_id,
    CAST(a.batch_id AS NVARCHAR(36)) AS batch_id,
    a.pipeline_run_id,
    a.run_type,
    a.load_strategy,
    a.status,
    a.source_row_count,
    a.target_row_count,
    a.duration_seconds,
    a.start_time,
    a.end_time,
    a.error_code,
    a.error_message
FROM audit.ingestion_log AS a;
GO

SELECT source_system, batch_id, source_status, object_count,
       success_count, skipped_count, failed_count, batch_end_time
FROM audit.v_monitor_latest_source
ORDER BY source_system;
GO

SELECT TOP (20) source_system, source_entity, status, end_time,
                error_code
FROM audit.v_monitor_object_history
ORDER BY end_time DESC, ingestion_log_id DESC;
GO
