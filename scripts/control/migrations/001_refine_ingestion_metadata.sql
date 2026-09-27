/*
    001_refine_ingestion_metadata.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Non-destructive M76 metadata migration.

    Final M76 metadata direction:
      - source_path: physical/logical source location or identifier
      - source_options: optional pattern-specific source-reading options (JSON)
      - landing_path: Landing Zone path for patterns that use Landing
      - source_schema may be NULL for non-DATABASE patterns
      - no separate file_ingestion_config table
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

IF COL_LENGTH('control.ingestion_config', 'source_path') IS NULL
BEGIN
    ALTER TABLE control.ingestion_config
    ADD source_path NVARCHAR(1000) NULL;
END;
GO

IF COL_LENGTH('control.ingestion_config', 'source_options') IS NULL
BEGIN
    ALTER TABLE control.ingestion_config
    ADD source_options NVARCHAR(MAX) NULL;
END;
GO

IF COL_LENGTH('control.ingestion_config', 'landing_path') IS NULL
BEGIN
    ALTER TABLE control.ingestion_config
    ADD landing_path NVARCHAR(1000) NULL;
END;
GO

IF COL_LENGTH('control.ingestion_config', 'target_folder') IS NOT NULL
BEGIN
    UPDATE control.ingestion_config
    SET landing_path = COALESCE(landing_path, target_folder)
    WHERE target_folder IS NOT NULL;

    IF EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE name = 'CK_ingestion_config_target_folder'
          AND parent_object_id = OBJECT_ID('control.ingestion_config')
    )
    BEGIN
        ALTER TABLE control.ingestion_config
        DROP CONSTRAINT CK_ingestion_config_target_folder;
    END;

    ALTER TABLE control.ingestion_config
    DROP COLUMN target_folder;
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
    WHERE name = 'CK_ingestion_config_source_path'
      AND parent_object_id = OBJECT_ID('control.ingestion_config')
)
BEGIN
    ALTER TABLE control.ingestion_config
    ADD CONSTRAINT CK_ingestion_config_source_path
        CHECK
        (
            (ingestion_pattern = 'FILE' AND source_path IS NOT NULL)
            OR
            (ingestion_pattern IN ('DATABASE','API'))
        );
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_ingestion_config_landing_path'
      AND parent_object_id = OBJECT_ID('control.ingestion_config')
)
BEGIN
    ALTER TABLE control.ingestion_config
    ADD CONSTRAINT CK_ingestion_config_landing_path
        CHECK
        (
            (ingestion_pattern = 'FILE' AND landing_path IS NOT NULL)
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
    source_path,
    ingestion_pattern,
    source_options,
    landing_path,
    load_strategy
FROM control.ingestion_config
ORDER BY ingestion_config_id;
GO
