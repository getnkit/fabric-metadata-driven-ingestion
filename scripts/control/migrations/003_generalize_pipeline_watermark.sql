/*
    003_generalize_pipeline_watermark.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)

    Purpose:
      - Generalize control.pipeline_watermarks so DATABASE, FILE, and future API
        ingestion patterns can share the same persistent checkpoint table.
      - Store last_watermark_value as STRING rather than DATETIME2.
      - Keep existing DATABASE watermark values in ISO-8601 text format.
      - Update control.usp_finalize_ingestion_run so callers can advance either
        datetime LOW/HIGH bounds or generic string checkpoint values.

    FILE incremental contract used by the first implementation:
      - watermark_field = source_file_name
      - filenames are immutable, unique, fixed-width, and monotonically sortable
      - example: inventory_movement_20260927_001.csv
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ExistingWatermarks TABLE
(
    ingestion_config_id       INT PRIMARY KEY,
    last_watermark_value_text NVARCHAR(1000) NOT NULL
);

INSERT INTO @ExistingWatermarks
(
    ingestion_config_id,
    last_watermark_value_text
)
SELECT
    ingestion_config_id,
    CONVERT(NVARCHAR(40), last_watermark_value, 126)
FROM control.pipeline_watermarks;

IF OBJECT_ID('control.v_pipeline_watermarks', 'V') IS NOT NULL
    DROP VIEW control.v_pipeline_watermarks;

ALTER TABLE control.pipeline_watermarks
    ALTER COLUMN last_watermark_value NVARCHAR(1000) NOT NULL;

UPDATE w
SET w.last_watermark_value = e.last_watermark_value_text
FROM control.pipeline_watermarks w
JOIN @ExistingWatermarks e
  ON e.ingestion_config_id = w.ingestion_config_id;

IF EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_ingestion_config_watermark'
      AND parent_object_id = OBJECT_ID('control.ingestion_config')
)
BEGIN
    ALTER TABLE control.ingestion_config
        DROP CONSTRAINT CK_ingestion_config_watermark;
END;

ALTER TABLE control.ingestion_config
ADD CONSTRAINT CK_ingestion_config_watermark
    CHECK
    (
        (load_strategy = 'FULL' AND watermark_field IS NULL)
        OR
        (load_strategy = 'INCREMENTAL' AND watermark_field IS NOT NULL)
    );

IF OBJECT_ID('control.usp_mark_file_processed', 'P') IS NOT NULL
    DROP PROCEDURE control.usp_mark_file_processed;

IF OBJECT_ID('control.file_ingestion_state', 'U') IS NOT NULL
    DROP TABLE control.file_ingestion_state;
GO

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

PRINT 'Pipeline watermark state generalized successfully.';
PRINT 'Next: run scripts/control/02_create_control_procedures.sql to refresh the generic finalization procedure.';
GO
