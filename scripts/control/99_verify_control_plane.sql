/*
  99_verify_control_plane.sql
  Read-only verification of fresh install / upgraded Personal Control Plane.
  Fails if required objects or constraints are missing/disabled/untrusted.
  Does NOT change SQL schema, configuration, watermark, or audit history.
*/
SET NOCOUNT ON;
GO

IF EXISTS (
    SELECT 1 FROM (VALUES
        (N'control', N'connection_settings'),
        (N'control', N'ingestion_config'),
        (N'control', N'pipeline_watermarks'),
        (N'audit', N'ingestion_log')
    ) AS expected(schema_name, table_name)
    WHERE OBJECT_ID(QUOTENAME(expected.schema_name) + N'.' + QUOTENAME(expected.table_name), N'U') IS NULL
)
    THROW 51200, 'VERIFY_FAILED: required control/audit table missing.', 1;

IF OBJECT_ID(N'control.v_pipeline_watermarks', N'V') IS NULL
    THROW 51201, 'VERIFY_FAILED: control.v_pipeline_watermarks view missing.', 1;

IF COL_LENGTH(N'audit.ingestion_log', N'landing_path') IS NULL
   OR COL_LENGTH(N'audit.ingestion_log', N'target_path') IS NOT NULL
    THROW 51202, 'VERIFY_FAILED: audit.ingestion_log must use landing_path (not legacy target_path).', 1;

IF OBJECT_ID(N'control.usp_finalize_ingestion_run', N'P') IS NULL
   OR OBJECT_ID(N'control.usp_validate_run_requests', N'P') IS NULL
    THROW 51203, 'VERIFY_FAILED: required ingestion Stored Procedure missing.', 1;

IF EXISTS (
    SELECT 1 FROM (VALUES
        (N'control', N'connection_settings', N'CK_connection_settings_type'),
        (N'control', N'connection_settings', N'CK_connection_settings_json'),
        (N'control', N'connection_settings', N'CK_connection_settings_ref_not_blank'),
        (N'control', N'ingestion_config', N'CK_ingestion_config_pattern'),
        (N'control', N'ingestion_config', N'CK_ingestion_config_file_format'),
        (N'control', N'ingestion_config', N'CK_ingestion_config_source_options_json'),
        (N'control', N'ingestion_config', N'CK_ingestion_config_copy_options_json'),
        (N'control', N'ingestion_config', N'CK_ingestion_config_source_schema'),
        (N'control', N'ingestion_config', N'CK_ingestion_config_source_path'),
        (N'control', N'ingestion_config', N'CK_ingestion_config_landing_path'),
        (N'control', N'ingestion_config', N'CK_ingestion_config_strategy'),
        (N'control', N'ingestion_config', N'CK_ingestion_config_watermark'),
        (N'control', N'ingestion_config', N'CK_ingestion_config_required_text'),
        (N'control', N'pipeline_watermarks', N'CK_pipeline_watermarks_required_text'),
        (N'audit', N'ingestion_log', N'CK_ingestion_log_run_type'),
        (N'audit', N'ingestion_log', N'CK_ingestion_log_status'),
        (N'audit', N'ingestion_log', N'CK_ingestion_log_counts'),
        (N'audit', N'ingestion_log', N'CK_ingestion_log_duration'),
        (N'audit', N'ingestion_log', N'CK_ingestion_log_time'),
        (N'audit', N'ingestion_log', N'CK_ingestion_log_required_text'),
        (N'audit', N'ingestion_log', N'CK_ingestion_log_load_strategy')
    ) AS expected(schema_name, table_name, constraint_name)
    WHERE NOT EXISTS (
        SELECT 1 FROM sys.check_constraints AS cc
        WHERE cc.parent_object_id = OBJECT_ID(QUOTENAME(expected.schema_name) + N'.' + QUOTENAME(expected.table_name))
          AND cc.name = expected.constraint_name
          AND cc.is_disabled = 0 AND cc.is_not_trusted = 0
    )
)
    THROW 51204, 'VERIFY_FAILED: required CHECK constraint missing, disabled or untrusted.', 1;

IF EXISTS (
    SELECT 1 FROM (VALUES
        (N'control', N'connection_settings', N'PK_connection_settings', N'PK'),
        (N'control', N'ingestion_config', N'PK_ingestion_config', N'PK'),
        (N'control', N'ingestion_config', N'UQ_ingestion_config_source', N'UQ'),
        (N'control', N'pipeline_watermarks', N'PK_pipeline_watermarks', N'PK'),
        (N'audit', N'ingestion_log', N'PK_ingestion_log', N'PK'),
        (N'audit', N'ingestion_log', N'UQ_ingestion_log_pipeline_run', N'UQ')
    ) AS expected(schema_name, table_name, key_name, key_type)
    WHERE NOT EXISTS (
        SELECT 1 FROM sys.key_constraints AS k
        INNER JOIN sys.indexes AS ix
            ON ix.object_id = k.parent_object_id
           AND ix.index_id = k.unique_index_id
        WHERE k.parent_object_id = OBJECT_ID(QUOTENAME(expected.schema_name) + N'.' + QUOTENAME(expected.table_name))
          AND k.name = expected.key_name AND k.type = expected.key_type
          AND ix.is_unique = 1 AND ix.is_disabled = 0
    )
)
    THROW 51205, 'VERIFY_FAILED: PK or UNIQUE constraint/index missing or disabled.', 1;

IF EXISTS (
    SELECT 1 FROM (VALUES
        (N'control', N'ingestion_config', N'FK_ingestion_config_source_connection'),
        (N'control', N'ingestion_config', N'FK_ingestion_config_target_connection'),
        (N'control', N'pipeline_watermarks', N'FK_pipeline_watermarks_config')
    ) AS expected(schema_name, table_name, fk_name)
    WHERE NOT EXISTS (
        SELECT 1 FROM sys.foreign_keys AS fk
        WHERE fk.parent_object_id = OBJECT_ID(QUOTENAME(expected.schema_name) + N'.' + QUOTENAME(expected.table_name))
          AND fk.name = expected.fk_name
          AND fk.is_disabled = 0 AND fk.is_not_trusted = 0
    )
)
    THROW 51206, 'VERIFY_FAILED: required FOREIGN KEY missing, disabled or untrusted.', 1;

IF EXISTS (
    SELECT 1 FROM (VALUES
        (N'IX_ingestion_log_batch'),
        (N'IX_ingestion_log_config_time'),
        (N'IX_ingestion_log_status_time')
    ) AS expected(index_name)
    WHERE NOT EXISTS (
        SELECT 1 FROM sys.indexes AS ix
        WHERE ix.object_id = OBJECT_ID(N'audit.ingestion_log')
          AND ix.name = expected.index_name
          AND ix.is_disabled = 0
    )
)
    THROW 51207, 'VERIFY_FAILED: ingestion audit query index missing or disabled.', 1;

SELECT
    OBJECT_SCHEMA_NAME(t.object_id) AS schema_name,
    t.name AS table_name,
    COUNT(c.column_id) AS column_count
FROM sys.tables AS t
JOIN sys.columns AS c ON c.object_id = t.object_id
WHERE t.object_id IN (OBJECT_ID(N'control.connection_settings'),
                     OBJECT_ID(N'control.ingestion_config'),
                     OBJECT_ID(N'control.pipeline_watermarks'),
                     OBJECT_ID(N'audit.ingestion_log'))
GROUP BY t.object_id, t.name
ORDER BY schema_name, t.name;

PRINT 'Control Plane verification passed: tables, view, stored procedures, PK/UQ, FK, CHECK and audit indexes.';
GO
