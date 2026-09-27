/*
    001_add_source_options.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Non-destructive M76 metadata migration.

    Changes:
      - allow source_schema to be NULL for non-DATABASE ingestion patterns
      - add source_options as optional JSON metadata
      - require target_folder for FILE configs
      - remove the abandoned file_ingestion_config table only if it exists and is empty
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID('control.file_ingestion_config', 'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM control.file_ingestion_config)
        THROW 51000, 'Legacy control.file_ingestion_config contains data; review before dropping.', 1;

    DROP TABLE control.file_ingestion_config;
END;
GO

ALTER TABLE control.ingestion_config
ALTER COLUMN source_schema NVARCHAR(128) NULL;
GO

IF COL_LENGTH('control.ingestion_config', 'source_options') IS NULL
BEGIN
    ALTER TABLE control.ingestion_config
    ADD source_options NVARCHAR(MAX) NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_ingestion_config_source_options_json'
      AND parent_object_id = OBJECT_ID('control.ingestion_config')
)
BEGIN
    ALTER TABLE control.ingestion_config
    ADD CONSTRAINT CK_ingestion_config_source_options_json
        CHECK (source_options IS NULL OR ISJSON(source_options) = 1);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_ingestion_config_source_schema'
      AND parent_object_id = OBJECT_ID('control.ingestion_config')
)
BEGIN
    ALTER TABLE control.ingestion_config
    ADD CONSTRAINT CK_ingestion_config_source_schema
        CHECK
        (
            (ingestion_pattern = 'DATABASE' AND source_schema IS NOT NULL)
            OR
            (ingestion_pattern IN ('FILE','API'))
        );
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_ingestion_config_target_folder'
      AND parent_object_id = OBJECT_ID('control.ingestion_config')
)
BEGIN
    ALTER TABLE control.ingestion_config
    ADD CONSTRAINT CK_ingestion_config_target_folder
        CHECK
        (
            (ingestion_pattern = 'FILE' AND target_folder IS NOT NULL)
            OR
            (ingestion_pattern IN ('DATABASE','API'))
        );
END;
GO

SELECT
    ingestion_config_id,
    source_system,
    source_schema,
    source_object,
    ingestion_pattern,
    source_options,
    target_folder,
    load_strategy
FROM control.ingestion_config
ORDER BY ingestion_config_id;
GO
