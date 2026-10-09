/*
  011_harden_control_plane_constraints.sql
  Upgrade existing Personal Fabric SQL control plane, NOT a fresh install.
  Preserve metadata/audit/watermark values. No automatic data remediation.
  Requires historical structural migrations 001-010 where applicable.
  Does NOT deploy Stored Procedures. Run 99 after successful application.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'control.connection_settings', N'U') IS NULL
       OR OBJECT_ID(N'control.ingestion_config', N'U') IS NULL
       OR OBJECT_ID(N'control.pipeline_watermarks', N'U') IS NULL
       OR OBJECT_ID(N'audit.ingestion_log', N'U') IS NULL
        THROW 51100, 'MISSING_TABLE: apply earlier structural migrations before 011.', 1;

    IF COL_LENGTH(N'audit.ingestion_log', N'landing_path') IS NULL
        THROW 51101, 'AUDIT_SCHEMA_MISMATCH: landing_path missing; finish previous migrations.', 1;

    -- Preflight before any DDL. A failed migration rolls back all changes.
    IF EXISTS (SELECT 1 FROM control.connection_settings
               WHERE LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM connection_ref)) = 0
                  OR ISNULL(ISJSON(connection_settings, OBJECT), 0) <> 1)
        THROW 51102, 'INVALID_CONNECTION_METADATA: blank reference or JSON root not object.', 1;

    IF EXISTS (SELECT 1 FROM control.ingestion_config
               WHERE LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_system)) = 0
           OR LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_conn_ref)) = 0
           OR LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_object)) = 0
           OR LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM target_conn_ref)) = 0
           OR LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM target_schema)) = 0
           OR LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM target_table)) = 0
                  OR (ingestion_pattern = 'DATABASE'
                      AND (source_schema IS NULL OR LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_schema)) = 0))
                  OR (ingestion_pattern = 'FILE'
                      AND (source_path IS NULL OR LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_path)) = 0))
                  OR (load_strategy = 'INCREMENTAL'
                      AND (watermark_field IS NULL OR LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM watermark_field)) = 0))
                  OR (ingestion_pattern = 'FILE' AND (file_format IS NULL OR file_format NOT IN ('DELIMITED_TEXT','PARQUET','JSON')))
                  OR (ingestion_pattern IN ('DATABASE','API') AND file_format IS NOT NULL)
                  OR (load_strategy = 'FULL' AND watermark_field IS NOT NULL)
                  OR (source_options IS NOT NULL
                      AND ISNULL(ISJSON(source_options, OBJECT), 0) <> 1)
                  OR (copy_options IS NOT NULL
                      AND ISNULL(ISJSON(copy_options, OBJECT), 0) <> 1))
        THROW 51103, 'INVALID_INGESTION_METADATA: inspect blank required fields, watermark and JSON roots.', 1;

    IF EXISTS (SELECT 1 FROM control.pipeline_watermarks
               WHERE LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM watermark_field)) = 0
                  OR LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM last_watermark_value)) = 0)
        THROW 51104, 'INVALID_WATERMARK_STATE: blank watermark field or checkpoint.', 1;

    IF EXISTS (SELECT 1 FROM audit.ingestion_log
               WHERE LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM pipeline_run_id)) = 0
                  OR LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM pipeline_name)) = 0
                  OR (load_strategy IS NOT NULL
                      AND load_strategy NOT IN ('FULL', 'INCREMENTAL')))
        THROW 51105, 'INVALID_AUDIT_HISTORY: blank run identity or unsupported load_strategy.', 1;

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'control.connection_settings')
                 AND name = N'CK_connection_settings_ref_not_blank')
        ALTER TABLE control.connection_settings DROP CONSTRAINT CK_connection_settings_ref_not_blank;

    ALTER TABLE control.connection_settings WITH CHECK
        ADD CONSTRAINT CK_connection_settings_ref_not_blank CHECK (LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM connection_ref)) > 0);

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'control.connection_settings')
                 AND name = N'CK_connection_settings_json')
        ALTER TABLE control.connection_settings DROP CONSTRAINT CK_connection_settings_json;

    ALTER TABLE control.connection_settings WITH CHECK
        ADD CONSTRAINT CK_connection_settings_json CHECK (ISJSON(connection_settings, OBJECT) = 1);

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'control.ingestion_config')
                 AND name = N'CK_ingestion_config_file_format')
        ALTER TABLE control.ingestion_config DROP CONSTRAINT CK_ingestion_config_file_format;

    ALTER TABLE control.ingestion_config WITH CHECK
        ADD CONSTRAINT CK_ingestion_config_file_format CHECK (
            (ingestion_pattern = 'FILE' AND file_format IS NOT NULL AND file_format IN ('DELIMITED_TEXT','PARQUET','JSON'))
            OR (ingestion_pattern IN ('DATABASE','API') AND file_format IS NULL)
        );

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'control.ingestion_config')
                 AND name = N'CK_ingestion_config_required_text')
        ALTER TABLE control.ingestion_config DROP CONSTRAINT CK_ingestion_config_required_text;

    ALTER TABLE control.ingestion_config WITH CHECK
        ADD CONSTRAINT CK_ingestion_config_required_text CHECK (LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_system))>0 AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_conn_ref))>0 AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_object))>0 AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM target_conn_ref))>0 AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM target_schema))>0 AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM target_table))>0);

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'control.ingestion_config')
                 AND name = N'CK_ingestion_config_source_options_json')
        ALTER TABLE control.ingestion_config DROP CONSTRAINT CK_ingestion_config_source_options_json;

    ALTER TABLE control.ingestion_config WITH CHECK
        ADD CONSTRAINT CK_ingestion_config_source_options_json CHECK (source_options IS NULL OR ISJSON(source_options, OBJECT) = 1);

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'control.ingestion_config')
                 AND name = N'CK_ingestion_config_copy_options_json')
        ALTER TABLE control.ingestion_config DROP CONSTRAINT CK_ingestion_config_copy_options_json;

    ALTER TABLE control.ingestion_config WITH CHECK
        ADD CONSTRAINT CK_ingestion_config_copy_options_json CHECK (copy_options IS NULL OR ISJSON(copy_options, OBJECT) = 1);

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'control.ingestion_config')
                 AND name = N'CK_ingestion_config_source_schema')
        ALTER TABLE control.ingestion_config DROP CONSTRAINT CK_ingestion_config_source_schema;

    ALTER TABLE control.ingestion_config WITH CHECK
        ADD CONSTRAINT CK_ingestion_config_source_schema CHECK (ingestion_pattern <> 'DATABASE' OR (source_schema IS NOT NULL AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_schema)) > 0));

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'control.ingestion_config')
                 AND name = N'CK_ingestion_config_source_path')
        ALTER TABLE control.ingestion_config DROP CONSTRAINT CK_ingestion_config_source_path;

    ALTER TABLE control.ingestion_config WITH CHECK
        ADD CONSTRAINT CK_ingestion_config_source_path CHECK (ingestion_pattern <> 'FILE' OR (source_path IS NOT NULL AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_path)) > 0));

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'control.ingestion_config')
                 AND name = N'CK_ingestion_config_watermark')
        ALTER TABLE control.ingestion_config DROP CONSTRAINT CK_ingestion_config_watermark;

    ALTER TABLE control.ingestion_config WITH CHECK
        ADD CONSTRAINT CK_ingestion_config_watermark CHECK ((load_strategy = 'FULL' AND watermark_field IS NULL) OR (load_strategy = 'INCREMENTAL' AND watermark_field IS NOT NULL AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM watermark_field)) > 0));

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'control.pipeline_watermarks')
                 AND name = N'CK_pipeline_watermarks_required_text')
        ALTER TABLE control.pipeline_watermarks DROP CONSTRAINT CK_pipeline_watermarks_required_text;

    ALTER TABLE control.pipeline_watermarks WITH CHECK
        ADD CONSTRAINT CK_pipeline_watermarks_required_text CHECK (LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM watermark_field)) > 0 AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM last_watermark_value)) > 0);

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'audit.ingestion_log')
                 AND name = N'CK_ingestion_log_required_text')
        ALTER TABLE audit.ingestion_log DROP CONSTRAINT CK_ingestion_log_required_text;

    ALTER TABLE audit.ingestion_log WITH CHECK
        ADD CONSTRAINT CK_ingestion_log_required_text CHECK (LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM pipeline_run_id)) > 0 AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM pipeline_name)) > 0);

    IF EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'audit.ingestion_log')
                 AND name = N'CK_ingestion_log_load_strategy')
        ALTER TABLE audit.ingestion_log DROP CONSTRAINT CK_ingestion_log_load_strategy;

    ALTER TABLE audit.ingestion_log WITH CHECK
        ADD CONSTRAINT CK_ingestion_log_load_strategy CHECK (load_strategy IS NULL OR load_strategy IN ('FULL','INCREMENTAL'));

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

-- Check that all updated constraints are enabled and trusted.
SELECT cc.name, cc.is_disabled, cc.is_not_trusted
FROM sys.check_constraints AS cc
WHERE cc.name IN (
    N'CK_connection_settings_ref_not_blank',
    N'CK_connection_settings_json',
    N'CK_ingestion_config_file_format',
    N'CK_ingestion_config_required_text',
    N'CK_ingestion_config_source_options_json',
    N'CK_ingestion_config_copy_options_json',
    N'CK_ingestion_config_source_schema',
    N'CK_ingestion_config_source_path',
    N'CK_ingestion_config_watermark',
    N'CK_pipeline_watermarks_required_text',
    N'CK_ingestion_log_required_text',
    N'CK_ingestion_log_load_strategy'
)
ORDER BY cc.name;
GO
