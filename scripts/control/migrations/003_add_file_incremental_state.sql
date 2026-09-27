/*
    003_add_file_incremental_state.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose:
      - Allow FILE + INCREMENTAL configs to use file-processing state instead
        of relational watermark columns.
      - Create processed-file state used to skip files that have already been
        committed to Bronze.
      - Create the idempotent state-marking procedure required by the
        FILE incremental pipeline.

    File identity contract:
      - An incremental file name is unique within one ingestion config.
      - Once delivered, an incremental source file is immutable.
      - Replacing file contents under the same file name is a producer-side
        contract violation and is intentionally not treated as a new file.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID('control.ingestion_config', 'U') IS NULL
    THROW 51020, 'MISSING_CONTROL_SCHEMA: control.ingestion_config does not exist.', 1;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_ingestion_config_watermark'
      AND parent_object_id = OBJECT_ID('control.ingestion_config')
)
BEGIN
    ALTER TABLE control.ingestion_config
        DROP CONSTRAINT CK_ingestion_config_watermark;
END;
GO

ALTER TABLE control.ingestion_config
ADD CONSTRAINT CK_ingestion_config_watermark
    CHECK
    (
        (load_strategy = 'FULL' AND watermark_field IS NULL)
        OR
        (
            load_strategy = 'INCREMENTAL'
            AND ingestion_pattern = 'DATABASE'
            AND watermark_field IS NOT NULL
        )
        OR
        (
            load_strategy = 'INCREMENTAL'
            AND ingestion_pattern = 'FILE'
            AND watermark_field IS NULL
        )
        OR
        (
            load_strategy = 'INCREMENTAL'
            AND ingestion_pattern = 'API'
        )
    );
GO

IF OBJECT_ID('control.file_ingestion_state', 'U') IS NULL
BEGIN
    CREATE TABLE control.file_ingestion_state
    (
        file_ingestion_state_id          BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_file_ingestion_state PRIMARY KEY,

        ingestion_config_id              INT NOT NULL,
        source_file_name                 NVARCHAR(512) NOT NULL,
        source_file_path                 NVARCHAR(1500) NOT NULL,
        landing_file_path                NVARCHAR(1500) NOT NULL,

        processed_batch_id               UNIQUEIDENTIFIER NOT NULL,
        processed_pipeline_run_id        NVARCHAR(100) NOT NULL,
        processed_at                     DATETIME2(3) NOT NULL
            CONSTRAINT DF_file_ingestion_state_processed_at DEFAULT SYSUTCDATETIME(),

        CONSTRAINT UQ_file_ingestion_state_file
            UNIQUE (ingestion_config_id, source_file_name),

        CONSTRAINT FK_file_ingestion_state_config
            FOREIGN KEY (ingestion_config_id)
            REFERENCES control.ingestion_config(ingestion_config_id)
    );

    CREATE INDEX IX_file_ingestion_state_processed_at
        ON control.file_ingestion_state(ingestion_config_id, processed_at DESC);
END;
GO

CREATE OR ALTER PROCEDURE control.usp_mark_file_processed
    @ingestion_config_id        INT,
    @source_file_name           NVARCHAR(512),
    @source_file_path           NVARCHAR(1500),
    @landing_file_path          NVARCHAR(1500),
    @processed_batch_id         UNIQUEIDENTIFIER,
    @processed_pipeline_run_id  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS
    (
        SELECT 1
        FROM control.file_ingestion_state
        WHERE ingestion_config_id = @ingestion_config_id
          AND source_file_name = @source_file_name
    )
        RETURN 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS
        (
            SELECT 1
            FROM control.file_ingestion_state WITH (UPDLOCK, HOLDLOCK)
            WHERE ingestion_config_id = @ingestion_config_id
              AND source_file_name = @source_file_name
        )
        BEGIN
            INSERT INTO control.file_ingestion_state
            (
                ingestion_config_id,
                source_file_name,
                source_file_path,
                landing_file_path,
                processed_batch_id,
                processed_pipeline_run_id
            )
            VALUES
            (
                @ingestion_config_id,
                @source_file_name,
                @source_file_path,
                @landing_file_path,
                @processed_batch_id,
                @processed_pipeline_run_id
            );
        END;

        COMMIT TRANSACTION;
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

SELECT
    OBJECT_ID('control.file_ingestion_state', 'U') AS file_ingestion_state_object_id,
    OBJECT_ID('control.usp_mark_file_processed', 'P') AS mark_file_processed_procedure_id;
GO
