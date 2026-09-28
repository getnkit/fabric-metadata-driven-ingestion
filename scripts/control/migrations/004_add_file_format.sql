/*
    004_add_file_format.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)

    Purpose:
      - Promote FILE format from source_options JSON to first-class routing metadata.
      - Keep format-specific parser settings in source_options.
      - Preserve DATABASE/API rows with file_format = NULL.

    Current canonical values:
      DELIMITED_TEXT
      PARQUET
      JSON

    After this migration, rerun:
      scripts/control/04_seed_ingestion_metadata.sql
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('control.ingestion_config', 'U') IS NULL
    THROW 51030, 'MISSING_CONTROL_SCHEMA: control.ingestion_config does not exist.', 1;

IF COL_LENGTH('control.ingestion_config', 'file_format') IS NULL
BEGIN
    ALTER TABLE control.ingestion_config
        ADD file_format VARCHAR(30) NULL;
END;

/* Migrate the previous JSON-owned format into the routing column. */
UPDATE control.ingestion_config
SET file_format =
    CASE UPPER(COALESCE(JSON_VALUE(source_options, '$.file_format'), ''))
        WHEN 'CSV' THEN 'DELIMITED_TEXT'
        WHEN 'DELIMITED' THEN 'DELIMITED_TEXT'
        WHEN 'DELIMITEDTEXT' THEN 'DELIMITED_TEXT'
        WHEN 'DELIMITED_TEXT' THEN 'DELIMITED_TEXT'
        WHEN 'PARQUET' THEN 'PARQUET'
        WHEN 'JSON' THEN 'JSON'
        ELSE file_format
    END
WHERE ingestion_pattern = 'FILE'
  AND file_format IS NULL;

IF EXISTS
(
    SELECT 1
    FROM control.ingestion_config
    WHERE ingestion_pattern = 'FILE'
      AND file_format IS NULL
)
    THROW 51031, 'FILE_FORMAT_REQUIRED: one or more FILE configs cannot be mapped to a supported file_format.', 1;

/* file_format now owns routing; source_options keeps parser-specific options only. */
UPDATE control.ingestion_config
SET
    source_options = JSON_MODIFY(source_options, '$.file_format', NULL),
    updated_at = SYSUTCDATETIME()
WHERE ingestion_pattern = 'FILE'
  AND source_options IS NOT NULL
  AND JSON_VALUE(source_options, '$.file_format') IS NOT NULL;

IF EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_ingestion_config_file_format'
      AND parent_object_id = OBJECT_ID('control.ingestion_config')
)
BEGIN
    ALTER TABLE control.ingestion_config
        DROP CONSTRAINT CK_ingestion_config_file_format;
END;

ALTER TABLE control.ingestion_config
ADD CONSTRAINT CK_ingestion_config_file_format
    CHECK
    (
        (ingestion_pattern = 'FILE' AND file_format IN ('DELIMITED_TEXT','PARQUET','JSON'))
        OR
        (ingestion_pattern IN ('DATABASE','API') AND file_format IS NULL)
    );

PRINT 'FILE format promoted to control.ingestion_config.file_format.';
PRINT 'Next: rerun scripts/control/04_seed_ingestion_metadata.sql.';
GO
