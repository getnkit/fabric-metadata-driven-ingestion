/*
    008_require_file_name_pattern.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Require a non-blank source_options.file_name_pattern for FILE
             ingestion configurations. FILE source_object is a stable feed
             identifier; source_path is the physical source folder.

    Non-destructive: does not modify config IDs, existing values, audit, or
    control.pipeline_watermarks. Inspect/fix invalid FILE configs before rerun.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('control.ingestion_config', 'U') IS NULL
    THROW 51040, 'MISSING_CONTROL_SCHEMA: control.ingestion_config does not exist.', 1;

-- Existing invalid JSON options must be resolved before attempting JSON_VALUE.
IF EXISTS
(
    SELECT 1
    FROM control.ingestion_config
    WHERE ingestion_pattern = 'FILE'
      AND (source_options IS NULL OR ISJSON(source_options) <> 1)
)
    THROW 51041, 'INVALID_FILE_NAME_PATTERN: FILE source_options must be a valid JSON object containing file_name_pattern.', 1;

IF EXISTS
(
    SELECT 1
    FROM control.ingestion_config
    WHERE ingestion_pattern = 'FILE'
      AND NULLIF(TRIM(JSON_VALUE(source_options, '$.file_name_pattern')), '') IS NULL
)
    THROW 51042, 'INVALID_FILE_NAME_PATTERN: FILE source_options.file_name_pattern must be a non-blank string. Correct the affected ingestion configs before retrying.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_ingestion_config_file_name_pattern'
      AND parent_object_id = OBJECT_ID('control.ingestion_config')
)
BEGIN
    ALTER TABLE control.ingestion_config
    ADD CONSTRAINT CK_ingestion_config_file_name_pattern
        CHECK
        (
            ingestion_pattern <> 'FILE'
            OR
            (
                source_options IS NOT NULL
                AND ISJSON(source_options) = 1
                AND NULLIF(TRIM(JSON_VALUE(source_options, '$.file_name_pattern')), '') IS NOT NULL
            )
        );
END;

PRINT 'FILE metadata now requires a non-blank source_options.file_name_pattern.';
GO
