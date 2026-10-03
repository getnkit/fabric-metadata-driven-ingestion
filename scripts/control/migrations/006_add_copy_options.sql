/*
    006_add_copy_options.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Add optional connector/copy execution tuning metadata without
             expanding control.ingestion_config with connector-specific columns.

    copy_options semantics:
      - NULL = use the connector/service defaults.
      - JSON object = connector adapter may consume supported execution hints.
      - Current Azure SQL adapter supports:
          partition_option: NONE | DYNAMIC_RANGE
          partition_column: required for DYNAMIC_RANGE
          parallel_copies: optional positive integer override
        An omitted parallel_copies keeps Fabric service-managed parallelism.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH('control.ingestion_config', 'copy_options') IS NULL
BEGIN
    ALTER TABLE control.ingestion_config
    ADD copy_options NVARCHAR(MAX) NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_ingestion_config_copy_options_json'
      AND parent_object_id = OBJECT_ID('control.ingestion_config')
)
BEGIN
    ALTER TABLE control.ingestion_config
    ADD CONSTRAINT CK_ingestion_config_copy_options_json
        CHECK (copy_options IS NULL OR ISJSON(copy_options) = 1);
END;
GO

SELECT
    ingestion_config_id,
    source_system,
    source_schema,
    source_object,
    ingestion_pattern,
    load_strategy,
    copy_options
FROM control.ingestion_config
ORDER BY ingestion_config_id;
GO
