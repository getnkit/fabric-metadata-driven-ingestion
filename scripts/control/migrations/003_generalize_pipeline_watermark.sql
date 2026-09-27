/*
    003_generalize_pipeline_watermark.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)

    Final M76 state model:
      - control.pipeline_watermarks is shared by DATABASE, FILE, and future API patterns.
      - last_watermark_value is STRING so each adapter can persist its own checkpoint.
      - audit.processing_lower_bound / processing_upper_bound are also STRING.
      - No FILE-specific processed-state table is used.
      - FILE incremental uses Last Modified time as its first checkpoint mechanism.

    After this migration, run:
      scripts/control/02_create_control_procedures.sql
      scripts/control/04_seed_ingestion_metadata.sql
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('control.ingestion_config', 'U') IS NULL
    THROW 51020, 'MISSING_CONTROL_SCHEMA: control.ingestion_config does not exist.', 1;

IF OBJECT_ID('control.pipeline_watermarks', 'U') IS NULL
    THROW 51021, 'MISSING_WATERMARK_TABLE: control.pipeline_watermarks does not exist.', 1;

IF OBJECT_ID('audit.ingestion_log', 'U') IS NULL
    THROW 51022, 'MISSING_AUDIT_TABLE: audit.ingestion_log does not exist.', 1;

/* Preserve existing DATETIME watermark values in canonical ISO text before ALTER. */
IF EXISTS
(
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID('control.pipeline_watermarks')
      AND name = 'last_watermark_value'
      AND TYPE_NAME(user_type_id) <> 'nvarchar'
)
BEGIN
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
END;

/* Preserve existing DATETIME audit boundaries in canonical ISO text before ALTER. */
IF EXISTS
(
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID('audit.ingestion_log')
      AND name = 'processing_lower_bound'
      AND TYPE_NAME(user_type_id) <> 'nvarchar'
)
BEGIN
    DECLARE @ExistingAuditBounds TABLE
    (
        ingestion_log_id BIGINT PRIMARY KEY,
        lower_bound_text NVARCHAR(1000) NULL,
        upper_bound_text NVARCHAR(1000) NULL
    );

    INSERT INTO @ExistingAuditBounds
    (
        ingestion_log_id,
        lower_bound_text,
        upper_bound_text
    )
    SELECT
        ingestion_log_id,
        CASE
            WHEN processing_lower_bound IS NULL THEN NULL
            ELSE CONVERT(NVARCHAR(40), processing_lower_bound, 126)
        END,
        CASE
            WHEN processing_upper_bound IS NULL THEN NULL
            ELSE CONVERT(NVARCHAR(40), processing_upper_bound, 126)
        END
    FROM audit.ingestion_log;

    ALTER TABLE audit.ingestion_log
        ALTER COLUMN processing_lower_bound NVARCHAR(1000) NULL;

    ALTER TABLE audit.ingestion_log
        ALTER COLUMN processing_upper_bound NVARCHAR(1000) NULL;

    UPDATE l
    SET
        l.processing_lower_bound = b.lower_bound_text,
        l.processing_upper_bound = b.upper_bound_text
    FROM audit.ingestion_log l
    JOIN @ExistingAuditBounds b
      ON b.ingestion_log_id = l.ingestion_log_id;
END;

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

/* Remove the abandoned FILE-specific state prototype if it exists. */
IF OBJECT_ID('control.usp_mark_file_processed', 'P') IS NOT NULL
    DROP PROCEDURE control.usp_mark_file_processed;

IF OBJECT_ID('control.file_ingestion_state', 'U') IS NOT NULL
    DROP TABLE control.file_ingestion_state;

/*
    If the earlier filename-watermark prototype was ever seeded locally,
    move that one demo config to the final Last Modified checkpoint semantics.
*/
UPDATE control.ingestion_config
SET
    watermark_field = 'last_modified_time',
    updated_at = SYSUTCDATETIME()
WHERE source_system = 'LOGISTICS_VENDOR'
  AND source_object = 'inventory_movement'
  AND load_strategy = 'INCREMENTAL';

UPDATE w
SET
    w.watermark_field = 'last_modified_time',
    w.last_watermark_value = '1900-01-01T00:00:00.000Z',
    w.last_successful_batch_id = NULL,
    w.last_successful_pipeline_run_id = NULL,
    w.watermark_updated_at = SYSUTCDATETIME()
FROM control.pipeline_watermarks w
JOIN control.ingestion_config c
  ON c.ingestion_config_id = w.ingestion_config_id
WHERE c.source_system = 'LOGISTICS_VENDOR'
  AND c.source_object = 'inventory_movement'
  AND c.load_strategy = 'INCREMENTAL'
  AND
  (
      w.watermark_field <> 'last_modified_time'
      OR w.last_watermark_value LIKE 'inventory_movement_%'
      OR w.last_watermark_value = ''
  );

IF OBJECT_ID('control.v_pipeline_watermarks', 'V') IS NOT NULL
    DROP VIEW control.v_pipeline_watermarks;
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

PRINT 'Generic pipeline watermark and audit boundary migration completed.';
PRINT 'Next: run scripts/control/02_create_control_procedures.sql, then scripts/control/04_seed_ingestion_metadata.sql.';
GO
