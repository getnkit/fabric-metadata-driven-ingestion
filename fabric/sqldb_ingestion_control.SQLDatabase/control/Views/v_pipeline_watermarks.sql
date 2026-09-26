
CREATE VIEW control.v_pipeline_watermarks
AS
SELECT
    c.ingestion_config_id,
    c.source_system,
    c.source_schema,
    c.source_object,
    c.load_strategy,
    w.watermark_field,
    w.last_watermark_value,
    w.last_successful_batch_id,
    w.last_successful_pipeline_run_id,
    w.watermark_updated_at
FROM control.pipeline_watermarks w
JOIN control.ingestion_config c
    ON c.ingestion_config_id = w.ingestion_config_id;

GO

