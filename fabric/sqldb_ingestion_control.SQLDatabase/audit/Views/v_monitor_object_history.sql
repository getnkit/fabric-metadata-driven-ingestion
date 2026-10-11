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
