/*
    01_create_control_schema.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Create the metadata, current-state, and audit structures used by the
             metadata-driven ingestion framework.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF SCHEMA_ID('control') IS NULL EXEC('CREATE SCHEMA control');
IF SCHEMA_ID('audit') IS NULL EXEC('CREATE SCHEMA audit');
GO

IF OBJECT_ID('control.v_pipeline_watermarks', 'V') IS NOT NULL
    DROP VIEW control.v_pipeline_watermarks;
GO

IF OBJECT_ID('audit.ingestion_log', 'U') IS NOT NULL
    DROP TABLE audit.ingestion_log;
IF OBJECT_ID('control.pipeline_watermarks', 'U') IS NOT NULL
    DROP TABLE control.pipeline_watermarks;
IF OBJECT_ID('control.ingestion_config', 'U') IS NOT NULL
    DROP TABLE control.ingestion_config;
IF OBJECT_ID('control.connection_settings', 'U') IS NOT NULL
    DROP TABLE control.connection_settings;
GO

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
        CHECK (connection_type IN ('AZURE_SQL','LAKEHOUSE')),

    CONSTRAINT CK_connection_settings_json
        CHECK (ISJSON(connection_settings) = 1)
);
GO

CREATE TABLE control.ingestion_config
(
    ingestion_config_id  INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_ingestion_config PRIMARY KEY,

    source_system        NVARCHAR(100) NOT NULL,
    source_conn_ref      NVARCHAR(100) NOT NULL,
    source_schema        NVARCHAR(128) NOT NULL,
    source_object        NVARCHAR(128) NOT NULL,

    target_folder        NVARCHAR(500) NOT NULL,
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

    CONSTRAINT CK_ingestion_config_strategy
        CHECK (load_strategy IN ('FULL','INCREMENTAL')),

    CONSTRAINT CK_ingestion_config_watermark
        CHECK
        (
            (load_strategy = 'FULL' AND watermark_field IS NULL)
            OR
            (load_strategy = 'INCREMENTAL' AND watermark_field IS NOT NULL)
        ),

    CONSTRAINT FK_ingestion_config_source_connection
        FOREIGN KEY (source_conn_ref)
        REFERENCES control.connection_settings(connection_ref),

    CONSTRAINT FK_ingestion_config_target_connection
        FOREIGN KEY (target_conn_ref)
        REFERENCES control.connection_settings(connection_ref)
);
GO

CREATE TABLE control.pipeline_watermarks
(
    ingestion_config_id               INT NOT NULL
        CONSTRAINT PK_pipeline_watermarks PRIMARY KEY,

    watermark_field                   NVARCHAR(128) NOT NULL,
    last_watermark_value              DATETIME2(3) NOT NULL,

    last_successful_batch_id          UNIQUEIDENTIFIER NULL,
    last_successful_pipeline_run_id   NVARCHAR(100) NULL,

    watermark_updated_at              DATETIME2(3) NOT NULL
        CONSTRAINT DF_pipeline_watermarks_updated_at DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_pipeline_watermarks_config
        FOREIGN KEY (ingestion_config_id)
        REFERENCES control.ingestion_config(ingestion_config_id)
);
GO

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

    target_path               NVARCHAR(1000) NULL,
    target_conn_ref           NVARCHAR(100) NULL,
    target_schema             NVARCHAR(128) NULL,
    target_table              NVARCHAR(128) NULL,

    load_strategy             VARCHAR(20) NULL,
    watermark_field           NVARCHAR(128) NULL,

    processing_lower_bound    DATETIME2(3) NULL,
    processing_upper_bound    DATETIME2(3) NULL,

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

    CONSTRAINT CK_ingestion_log_run_type
        CHECK (run_type IN ('REGULAR','RERUN','BACKFILL')),

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
GO

CREATE INDEX IX_ingestion_log_batch
    ON audit.ingestion_log(batch_id, ingestion_log_id);
GO

CREATE INDEX IX_ingestion_log_config_time
    ON audit.ingestion_log(ingestion_config_id, start_time DESC);
GO

CREATE INDEX IX_ingestion_log_status_time
    ON audit.ingestion_log(status, start_time DESC);
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

PRINT 'Fabric control/state/audit schema created successfully.';
GO