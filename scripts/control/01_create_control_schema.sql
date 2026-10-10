/*
    01_create_control_schema.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Non-destructive fresh-install bootstrap for the Personal
             metadata-driven ingestion Control and Audit Plane.

    SQL Database Project definitions are the schema source of truth.
    CREATE-IF-ABSENT is NOT a schema migration: existing tables are preserved
    unchanged. Fresh installs should begin with empty Control/Audit tables.
    NEVER drop state or audit tables in a bootstrap.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF SCHEMA_ID('control') IS NULL EXEC('CREATE SCHEMA control');
IF SCHEMA_ID('audit') IS NULL EXEC('CREATE SCHEMA audit');
GO

IF OBJECT_ID(N'control.connection_settings', N'U') IS NULL
BEGIN
CREATE TABLE control.connection_settings
(
    connection_ref       NVARCHAR(100) NOT NULL
        CONSTRAINT PK_connection_settings PRIMARY KEY,

    connection_type      VARCHAR(50) NOT NULL,
    connection_settings  NVARCHAR(MAX) NOT NULL,

    created_at           DATETIME2(3) NOT NULL
        CONSTRAINT DF_connection_settings_created_at DEFAULT SYSUTCDATETIME(),

    updated_at           DATETIME2(3) NOT NULL
        CONSTRAINT DF_connection_settings_updated_at DEFAULT SYSUTCDATETIME(),

    CONSTRAINT CK_connection_settings_type
        CHECK (connection_type IN ('SQL_SERVER','SFTP','LAKEHOUSE')),

    CONSTRAINT CK_connection_settings_json
        CHECK (ISJSON(connection_settings, OBJECT) = 1),

    CONSTRAINT CK_connection_settings_ref_not_blank
        CHECK (LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM connection_ref)) > 0)
);
END;
GO

IF OBJECT_ID(N'control.ingestion_config', N'U') IS NULL
BEGIN
CREATE TABLE control.ingestion_config
(
    ingestion_config_id  INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_ingestion_config PRIMARY KEY,

    source_system        NVARCHAR(100) NOT NULL,
    source_conn_ref      NVARCHAR(100) NOT NULL,
    source_schema        NVARCHAR(128) NULL,
    source_object        NVARCHAR(128) NOT NULL,
    source_path          NVARCHAR(1000) NULL,

    ingestion_pattern    VARCHAR(20) NOT NULL,
    file_format          VARCHAR(30) NULL,
    source_options       NVARCHAR(MAX) NULL,
    copy_options         NVARCHAR(MAX) NULL,

    landing_path         NVARCHAR(1000) NULL,
    target_conn_ref      NVARCHAR(100) NOT NULL,
    target_schema        NVARCHAR(128) NOT NULL,
    target_table         NVARCHAR(128) NOT NULL,

    load_strategy        VARCHAR(20) NOT NULL,
    watermark_field      NVARCHAR(128) NULL,

    is_active            BIT NOT NULL
        CONSTRAINT DF_ingestion_config_is_active DEFAULT (1),

    created_at           DATETIME2(3) NOT NULL
        CONSTRAINT DF_ingestion_config_created_at DEFAULT SYSUTCDATETIME(),

    updated_at           DATETIME2(3) NOT NULL
        CONSTRAINT DF_ingestion_config_updated_at DEFAULT SYSUTCDATETIME(),

    CONSTRAINT UQ_ingestion_config_source
        UNIQUE (source_system, source_schema, source_object),

    CONSTRAINT CK_ingestion_config_pattern
        CHECK (ingestion_pattern IN ('DATABASE','FILE','API')),

    CONSTRAINT CK_ingestion_config_file_format
        CHECK
        (
            (ingestion_pattern = 'FILE' AND file_format IS NOT NULL AND file_format IN ('DELIMITED_TEXT','PARQUET','JSON'))
            OR
            (ingestion_pattern IN ('DATABASE','API') AND file_format IS NULL)
        ),

    CONSTRAINT CK_ingestion_config_required_text
        CHECK
        (
            LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_system)) > 0 AND
            LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_conn_ref)) > 0 AND
            LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_object)) > 0 AND
            LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM target_conn_ref)) > 0 AND
            LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM target_schema)) > 0 AND
            LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM target_table)) > 0
        ),

    CONSTRAINT CK_ingestion_config_source_options_json
        CHECK (source_options IS NULL OR ISJSON(source_options, OBJECT) = 1),

    CONSTRAINT CK_ingestion_config_copy_options_json
        CHECK (copy_options IS NULL OR ISJSON(copy_options, OBJECT) = 1),

    CONSTRAINT CK_ingestion_config_source_schema
        CHECK
        (
            (ingestion_pattern = 'DATABASE' AND source_schema IS NOT NULL AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_schema)) > 0)
            OR
            (ingestion_pattern IN ('FILE','API'))
        ),

    CONSTRAINT CK_ingestion_config_source_path
        CHECK
        (
            (ingestion_pattern = 'FILE' AND source_path IS NOT NULL AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM source_path)) > 0)
            OR
            (ingestion_pattern IN ('DATABASE','API'))
        ),

    CONSTRAINT CK_ingestion_config_landing_path
        CHECK
        (
            ingestion_pattern <> 'FILE'
            OR
            (
                landing_path IS NOT NULL
                AND TRIM(landing_path) <> ''
            )
        ),

    CONSTRAINT CK_ingestion_config_strategy
        CHECK (load_strategy IN ('FULL','INCREMENTAL')),

    CONSTRAINT CK_ingestion_config_watermark
        CHECK
        (
            (load_strategy = 'FULL' AND watermark_field IS NULL)
            OR
            (load_strategy = 'INCREMENTAL' AND watermark_field IS NOT NULL AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM watermark_field)) > 0)
        ),

    CONSTRAINT FK_ingestion_config_source_connection
        FOREIGN KEY (source_conn_ref)
        REFERENCES control.connection_settings(connection_ref),

    CONSTRAINT FK_ingestion_config_target_connection
        FOREIGN KEY (target_conn_ref)
        REFERENCES control.connection_settings(connection_ref)
);
END;
GO

IF OBJECT_ID(N'control.pipeline_watermarks', N'U') IS NULL
BEGIN
CREATE TABLE control.pipeline_watermarks
(
    ingestion_config_id               INT NOT NULL
        CONSTRAINT PK_pipeline_watermarks PRIMARY KEY,

    watermark_field                   NVARCHAR(128) NOT NULL,
    last_watermark_value              NVARCHAR(1000) NOT NULL,

    last_successful_batch_id          UNIQUEIDENTIFIER NULL,
    last_successful_pipeline_run_id   NVARCHAR(100) NULL,

    watermark_updated_at              DATETIME2(3) NOT NULL
        CONSTRAINT DF_pipeline_watermarks_updated_at DEFAULT SYSUTCDATETIME(),

    CONSTRAINT CK_pipeline_watermarks_required_text
        CHECK (LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM watermark_field)) > 0 AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM last_watermark_value)) > 0),

    CONSTRAINT FK_pipeline_watermarks_config
        FOREIGN KEY (ingestion_config_id)
        REFERENCES control.ingestion_config(ingestion_config_id)
);
END;
GO

IF OBJECT_ID(N'audit.ingestion_log', N'U') IS NULL
BEGIN
CREATE TABLE audit.ingestion_log
(
    ingestion_log_id          BIGINT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_ingestion_log PRIMARY KEY,

    ingestion_config_id       INT NULL,

    batch_id                  UNIQUEIDENTIFIER NOT NULL,
    pipeline_run_id           NVARCHAR(100) NOT NULL,
    pipeline_name             NVARCHAR(200) NOT NULL,

    run_type                  VARCHAR(20) NOT NULL,

    source_system             NVARCHAR(100) NULL,
    source_conn_ref           NVARCHAR(100) NULL,
    source_schema             NVARCHAR(128) NULL,
    source_object             NVARCHAR(128) NULL,
    source_path               NVARCHAR(1000) NULL,
    ingestion_pattern         VARCHAR(20) NULL,

    landing_path              NVARCHAR(1000) NULL,
    target_conn_ref           NVARCHAR(100) NULL,
    target_schema             NVARCHAR(128) NULL,
    target_table              NVARCHAR(128) NULL,

    load_strategy             VARCHAR(20) NULL,
    watermark_field           NVARCHAR(128) NULL,

    processing_lower_bound    NVARCHAR(1000) NULL,
    processing_upper_bound    NVARCHAR(1000) NULL,

    source_row_count          BIGINT NULL,
    target_row_count          BIGINT NULL,

    status                    VARCHAR(20) NOT NULL,

    error_code                NVARCHAR(100) NULL,
    error_message             NVARCHAR(4000) NULL,

    start_time                DATETIME2(3) NOT NULL,
    end_time                  DATETIME2(3) NOT NULL,
    duration_seconds          INT NOT NULL,

    log_timestamp             DATETIME2(3) NOT NULL
        CONSTRAINT DF_ingestion_log_timestamp DEFAULT SYSUTCDATETIME(),

    CONSTRAINT UQ_ingestion_log_pipeline_run
        UNIQUE (pipeline_run_id),

    CONSTRAINT CK_ingestion_log_required_text
        CHECK (LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM pipeline_run_id)) > 0 AND LEN(TRIM(NCHAR(9) + NCHAR(10) + NCHAR(13) + N' ' FROM pipeline_name)) > 0),

    CONSTRAINT CK_ingestion_log_load_strategy
        CHECK (load_strategy IS NULL OR load_strategy IN ('FULL','INCREMENTAL')),

    CONSTRAINT CK_ingestion_log_run_type
        CHECK (run_type IN ('REGULAR','BACKFILL')),

    CONSTRAINT CK_ingestion_log_status
        CHECK (status IN ('SUCCESS','FAILED','WARN','SKIPPED','CANCELLED')),

    CONSTRAINT CK_ingestion_log_counts
        CHECK
        (
            (source_row_count IS NULL OR source_row_count >= 0)
            AND
            (target_row_count IS NULL OR target_row_count >= 0)
        ),

    CONSTRAINT CK_ingestion_log_duration
        CHECK (duration_seconds >= 0),

    CONSTRAINT CK_ingestion_log_time
        CHECK (end_time >= start_time)
);
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'audit.ingestion_log') AND name = N'IX_ingestion_log_batch')
    CREATE INDEX IX_ingestion_log_batch
    ON audit.ingestion_log(batch_id, ingestion_log_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'audit.ingestion_log') AND name = N'IX_ingestion_log_config_time')
    CREATE INDEX IX_ingestion_log_config_time
    ON audit.ingestion_log(ingestion_config_id, start_time DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'audit.ingestion_log') AND name = N'IX_ingestion_log_status_time')
    CREATE INDEX IX_ingestion_log_status_time
    ON audit.ingestion_log(status, start_time DESC);
GO

CREATE OR ALTER VIEW control.v_pipeline_watermarks
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

PRINT 'Non-destructive Control/Audit bootstrap complete. Run scripts/control/99_verify_control_plane.sql to validate installed objects.';
GO