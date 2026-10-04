/*
    02_create_control_procedures.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Create the stored procedures used to finalize ingestion runs and update
             watermark state atomically.

    Core guarantees:
      1) Exactly one final audit record is stored for each Fabric child pipeline RunId.
      2) The watermark advances only after a successful run that processes data
         forward from the current watermark to a new upper bound.
      3) Watermark updates use an optimistic concurrency check:
         the stored watermark must still match the value read at the start of the run
         before it can be updated.
      4) The watermark state update and audit insert are committed together
         in a single SQL transaction.
      5) Retrying finalization for the same pipeline RunId is idempotent:
         it does not create duplicate audit records or advance the watermark twice.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE control.usp_finalize_ingestion_run
    @ingestion_config_id        INT = NULL,
    @batch_id                   UNIQUEIDENTIFIER,
    @pipeline_run_id            NVARCHAR(100),
    @pipeline_name              NVARCHAR(200),
    @run_type                   VARCHAR(20),

    @source_system              NVARCHAR(100) = NULL,
    @source_conn_ref            NVARCHAR(100) = NULL,
    @source_schema              NVARCHAR(128) = NULL,
    @source_object              NVARCHAR(128) = NULL,

    @landing_path                NVARCHAR(1000) = NULL,
    @target_conn_ref            NVARCHAR(100) = NULL,
    @target_schema              NVARCHAR(128) = NULL,
    @target_table               NVARCHAR(128) = NULL,

    @load_strategy              VARCHAR(20) = NULL,
    @watermark_field            NVARCHAR(128) = NULL,
    @processing_lower_bound     NVARCHAR(1000) = NULL,
    @processing_upper_bound     NVARCHAR(1000) = NULL,

    @source_row_count           BIGINT = NULL,
    @target_row_count           BIGINT = NULL,

    @status                     VARCHAR(20),
    @error_code                 NVARCHAR(100) = NULL,
    @error_message              NVARCHAR(4000) = NULL,

    @start_time                 DATETIME2(3),
    @end_time                   DATETIME2(3),

    @advance_watermark          BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ExistingStatus VARCHAR(20);
    DECLARE @DurationSeconds INT;
    DECLARE @ConflictMessage NVARCHAR(4000);
    DECLARE @ExpectedWatermark NVARCHAR(1000);
    DECLARE @NewWatermark NVARCHAR(1000);

    SET @DurationSeconds = DATEDIFF(SECOND, @start_time, @end_time);
    SET @ExpectedWatermark = @processing_lower_bound;
    SET @NewWatermark = @processing_upper_bound;

    /* BACKFILL is a run intent with its own historical scope, not a FULL/INCREMENTAL load strategy. */
    IF UPPER(@run_type) = 'BACKFILL'
        SET @load_strategy = NULL;

    IF @DurationSeconds < 0
        THROW 51000, 'INVALID_AUDIT_TIME_RANGE: end_time is earlier than start_time.', 1;

    SELECT @ExistingStatus = status
    FROM audit.ingestion_log
    WHERE pipeline_run_id = @pipeline_run_id;

    IF @ExistingStatus IS NOT NULL
    BEGIN
        IF @ExistingStatus = 'FAILED' AND @status = 'SUCCESS'
            THROW 51002, 'RUN_ALREADY_FINALIZED_AS_FAILED: this pipeline_run_id already has a FAILED audit record.', 1;

        RETURN 0;
    END;

    IF @advance_watermark = 1
    BEGIN
        IF @status NOT IN ('SUCCESS','SKIPPED')
            THROW 51003, 'INVALID_WATERMARK_ADVANCE: watermark can advance only for SUCCESS or SKIPPED.', 1;

        IF @ingestion_config_id IS NULL
           OR @watermark_field IS NULL
           OR @ExpectedWatermark IS NULL
           OR @NewWatermark IS NULL
            THROW 51004, 'INVALID_WATERMARK_ADVANCE: config, watermark field, current value, and new value are required.', 1;

        IF @NewWatermark = @ExpectedWatermark
            THROW 51005, 'INVALID_WATERMARK_ADVANCE: new watermark must differ from current watermark.', 1;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @advance_watermark = 1
        BEGIN
            UPDATE control.pipeline_watermarks
            SET
                last_watermark_value = @NewWatermark,
                last_successful_batch_id =
                    CASE WHEN @status = 'SUCCESS' THEN @batch_id ELSE last_successful_batch_id END,
                last_successful_pipeline_run_id =
                    CASE WHEN @status = 'SUCCESS' THEN @pipeline_run_id ELSE last_successful_pipeline_run_id END,
                watermark_updated_at = SYSUTCDATETIME()
            WHERE ingestion_config_id = @ingestion_config_id
              AND watermark_field = @watermark_field
              AND last_watermark_value = @ExpectedWatermark;

            IF @@ROWCOUNT <> 1
            BEGIN
                SET @ConflictMessage = CONCAT(
                    'Expected current watermark ',
                    @ExpectedWatermark,
                    ' for ingestion_config_id=',
                    CONVERT(NVARCHAR(20), @ingestion_config_id),
                    ', but the current state no longer matches.'
                );

                INSERT INTO audit.ingestion_log
                (
                    ingestion_config_id,
                    batch_id,
                    pipeline_run_id,
                    pipeline_name,
                    run_type,
                    source_system,
                    source_conn_ref,
                    source_schema,
                    source_object,
                    landing_path,
                    target_conn_ref,
                    target_schema,
                    target_table,
                    load_strategy,
                    watermark_field,
                    processing_lower_bound,
                    processing_upper_bound,
                    source_row_count,
                    target_row_count,
                    status,
                    error_code,
                    error_message,
                    start_time,
                    end_time,
                    duration_seconds
                )
                VALUES
                (
                    @ingestion_config_id,
                    @batch_id,
                    @pipeline_run_id,
                    @pipeline_name,
                    @run_type,
                    @source_system,
                    @source_conn_ref,
                    @source_schema,
                    @source_object,
                    @landing_path,
                    @target_conn_ref,
                    @target_schema,
                    @target_table,
                    @load_strategy,
                    @watermark_field,
                    @processing_lower_bound,
                    @processing_upper_bound,
                    @source_row_count,
                    @target_row_count,
                    'FAILED',
                    'WATERMARK_CONFLICT',
                    @ConflictMessage,
                    @start_time,
                    @end_time,
                    @DurationSeconds
                );

                COMMIT TRANSACTION;
                THROW 51006, 'WATERMARK_CONFLICT: current state changed before finalization.', 1;
            END;
        END;

        INSERT INTO audit.ingestion_log
        (
            ingestion_config_id,
            batch_id,
            pipeline_run_id,
            pipeline_name,
            run_type,
            source_system,
            source_conn_ref,
            source_schema,
            source_object,
            landing_path,
            target_conn_ref,
            target_schema,
            target_table,
            load_strategy,
            watermark_field,
            processing_lower_bound,
            processing_upper_bound,
            source_row_count,
            target_row_count,
            status,
            error_code,
            error_message,
            start_time,
            end_time,
            duration_seconds
        )
        VALUES
        (
            @ingestion_config_id,
            @batch_id,
            @pipeline_run_id,
            @pipeline_name,
            @run_type,
            @source_system,
            @source_conn_ref,
            @source_schema,
            @source_object,
            @landing_path,
            @target_conn_ref,
            @target_schema,
            @target_table,
            @load_strategy,
            @watermark_field,
            @processing_lower_bound,
            @processing_upper_bound,
            @source_row_count,
            @target_row_count,
            @status,
            @error_code,
            @error_message,
            @start_time,
            @end_time,
            @DurationSeconds
        );

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

PRINT 'control.usp_finalize_ingestion_run created successfully.';
GO
