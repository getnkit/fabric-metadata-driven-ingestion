/*
    001_add_file_ingestion_metadata.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Non-destructive M76 migration for FILE ingestion metadata.

    Safe for the current live project:
      - preserves existing ingestion configs, watermarks, and audit history
      - makes source_schema nullable for non-DATABASE patterns
      - enforces FILE landing-folder metadata
      - creates control.file_ingestion_config if missing
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

ALTER TABLE control.ingestion_config
ALTER COLUMN source_schema NVARCHAR(128) NULL;
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

IF OBJECT_ID('control.file_ingestion_config', 'U') IS NULL
BEGIN
    CREATE TABLE control.file_ingestion_config
    (
        ingestion_config_id  INT NOT NULL
            CONSTRAINT PK_file_ingestion_config PRIMARY KEY,

        source_folder        NVARCHAR(500) NOT NULL,
        file_name_pattern    NVARCHAR(255) NOT NULL,
        file_format          VARCHAR(20) NOT NULL,

        delimiter            NVARCHAR(10) NULL,
        has_header           BIT NULL,
        encoding             VARCHAR(30) NULL,

        expected_schema_json NVARCHAR(MAX) NOT NULL,
        quarantine_folder    NVARCHAR(500) NOT NULL,

        created_at           DATETIME2(3) NOT NULL
            CONSTRAINT DF_file_ingestion_config_created_at DEFAULT SYSUTCDATETIME(),

        updated_at           DATETIME2(3) NOT NULL
            CONSTRAINT DF_file_ingestion_config_updated_at DEFAULT SYSUTCDATETIME(),

        CONSTRAINT FK_file_ingestion_config_ingestion_config
            FOREIGN KEY (ingestion_config_id)
            REFERENCES control.ingestion_config(ingestion_config_id),

        CONSTRAINT CK_file_ingestion_config_format
            CHECK (file_format IN ('CSV','JSON','PARQUET')),

        CONSTRAINT CK_file_ingestion_config_schema_json
            CHECK (ISJSON(expected_schema_json) = 1),

        CONSTRAINT CK_file_ingestion_config_csv_options
            CHECK
            (
                (file_format = 'CSV' AND delimiter IS NOT NULL AND has_header IS NOT NULL)
                OR
                (file_format IN ('JSON','PARQUET'))
            )
    );
END;
GO

SELECT
    c.name AS constraint_name,
    OBJECT_NAME(c.parent_object_id) AS table_name
FROM sys.check_constraints c
WHERE c.parent_object_id = OBJECT_ID('control.ingestion_config')
  AND c.name IN
  (
      'CK_ingestion_config_source_schema',
      'CK_ingestion_config_target_folder'
  )
ORDER BY c.name;

SELECT
    OBJECT_ID('control.file_ingestion_config', 'U') AS file_ingestion_config_object_id;
GO
