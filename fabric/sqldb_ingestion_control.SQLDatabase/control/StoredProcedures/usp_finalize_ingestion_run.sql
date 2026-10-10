
CREATE   PROCEDURE control.usp_finalize_ingestion_run
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

    DECLARE @DurationSeconds INT;
    DECLARE @ConflictMessage NVARCHAR(4000);
    DECLARE @ExpectedWatermark NVARCHAR(1000);
    DECLARE @NewWatermark NVARCHAR(1000);
    DECLARE @AuditSourcePath NVARCHAR(1000);
    DECLARE @AuditIngestionPattern VARCHAR(20);

    SET @DurationSeconds = DATEDIFF(SECOND, @start_time, @end_time);
    SET @ExpectedWatermark = @processing_lower_bound;
    SET @NewWatermark = @processing_upper_bound;

    IF @DurationSeconds < 0
        THROW 51000, 'INVALID_AUDIT_TIME_RANGE: end_time is earlier than start_time.', 1;

    -- A retry is idempotent only when it matches the previously committed
    -- terminal audit outcome. A prior FAILED run must not masquerade as
    -- SUCCESS on a subsequent finalization attempt for the same RunId.
    IF EXISTS
    (
        SELECT 1
        FROM audit.ingestion_log
        WHERE pipeline_run_id = @pipeline_run_id
    )
    BEGIN
        IF EXISTS
        (
            SELECT 1
            FROM audit.ingestion_log AS a
            WHERE a.pipeline_run_id = @pipeline_run_id
              AND a.batch_id = @batch_id
              AND a.status = @status
              AND a.run_type = @run_type
              AND
              (
                  a.ingestion_config_id = @ingestion_config_id
                  OR (a.ingestion_config_id IS NULL AND @ingestion_config_id IS NULL)
              )
              AND
              (
                  a.error_code = @error_code
                  OR (a.error_code IS NULL AND @error_code IS NULL)
              )
              AND
              (
                  a.processing_lower_bound = @processing_lower_bound
                  OR (a.processing_lower_bound IS NULL AND @processing_lower_bound IS NULL)
              )
              AND
              (
                  a.processing_upper_bound = @processing_upper_bound
                  OR (a.processing_upper_bound IS NULL AND @processing_upper_bound IS NULL)
              )
        )
        BEGIN
            RETURN 0;
        END;

        THROW 51007, 'FINALIZE_OUTCOME_MISMATCH: existing audit does not match requested finalization.', 1;
    END;

    IF @advance_watermark = 1
    BEGIN
        IF @status <> 'SUCCESS'
            THROW 51003, 'INVALID_WATERMARK_ADVANCE: watermark can advance only for SUCCESS.', 1;

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

        -- Resolve source metadata for this log entry without new Pipeline parameters.
        SELECT
            @AuditSourcePath = c.source_path,
            @AuditIngestionPattern = c.ingestion_pattern
        FROM control.ingestion_config AS c
        WHERE c.ingestion_config_id = @ingestion_config_id;

        IF @advance_watermark = 1
        BEGIN
            UPDATE control.pipeline_watermarks
            SET
                last_watermark_value = @NewWatermark,
                last_successful_batch_id = @batch_id,
                last_successful_pipeline_run_id = @pipeline_run_id,
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
                    source_path,
                    ingestion_pattern,
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
                    @AuditSourcePath,
                    @AuditIngestionPattern,
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
            source_path,
            ingestion_pattern,
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
            @AuditSourcePath,
            @AuditIngestionPattern,
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

