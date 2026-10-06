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

    DECLARE @DurationSeconds INT;
    DECLARE @ConflictMessage NVARCHAR(4000);
    DECLARE @ExpectedWatermark NVARCHAR(1000);
    DECLARE @NewWatermark NVARCHAR(1000);

    SET @DurationSeconds = DATEDIFF(SECOND, @start_time, @end_time);
    SET @ExpectedWatermark = @processing_lower_bound;
    SET @NewWatermark = @processing_upper_bound;

    IF @DurationSeconds < 0
        THROW 51000, 'INVALID_AUDIT_TIME_RANGE: end_time is earlier than start_time.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM audit.ingestion_log
        WHERE pipeline_run_id = @pipeline_run_id
    )
    BEGIN
        RETURN 0;
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


/*
    Validate the top-level explicit run-request envelope before Dispatcher fan-out.

    This procedure validates only request shape and cross-request safety that can be
    decided without loading ingestion_config. Config-specific semantics (for example,
    FULL/INCREMENTAL boundary rules) remain owned by pl_ingest_object_controller.
*/
CREATE OR ALTER PROCEDURE control.usp_validate_run_requests
    @run_requests_json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    IF ISJSON(@run_requests_json, ARRAY) <> 1
    BEGIN
        THROW 51010, 'INVALID_RUN_REQUESTS: p_run_requests must be a JSON array.', 1;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM OPENJSON(@run_requests_json) AS request_item
        WHERE request_item.[type] <> 5
    )
    BEGIN
        THROW 51011, 'INVALID_RUN_REQUESTS: every p_run_requests item must be a JSON object.', 1;
    END;

    /*
        Required object contract:
          config_id   : positive integer
          run_type    : REGULAR | BACKFILL
          lower_bound : string or null
          upper_bound : string or null

        Bound semantics are intentionally not checked here because they depend on
        the config load_strategy and are validated by the Controller.
    */
    IF EXISTS
    (
        SELECT 1
        FROM OPENJSON(@run_requests_json) AS request_item
        WHERE
            NOT EXISTS
            (
                SELECT 1
                FROM OPENJSON(request_item.[value]) AS property
                WHERE property.[key] = 'config_id'
                  AND property.[type] = 2
                  AND TRY_CONVERT(INT, property.[value]) > 0
            )
            OR NOT EXISTS
            (
                SELECT 1
                FROM OPENJSON(request_item.[value]) AS property
                WHERE property.[key] = 'run_type'
                  AND property.[type] = 1
                  AND UPPER(property.[value]) IN ('REGULAR', 'BACKFILL')
            )
            OR NOT EXISTS
            (
                SELECT 1
                FROM OPENJSON(request_item.[value]) AS property
                WHERE property.[key] = 'lower_bound'
                  AND property.[type] IN (0, 1)
            )
            OR NOT EXISTS
            (
                SELECT 1
                FROM OPENJSON(request_item.[value]) AS property
                WHERE property.[key] = 'upper_bound'
                  AND property.[type] IN (0, 1)
            )
    )
    BEGIN
        THROW 51012, 'INVALID_RUN_REQUESTS: each request requires positive integer config_id, REGULAR/BACKFILL run_type, and lower_bound/upper_bound as string or null.', 1;
    END;

    DECLARE @DuplicateConfigIds NVARCHAR(MAX);
    DECLARE @DuplicateMessage NVARCHAR(2048);

    SELECT
        @DuplicateConfigIds =
            STRING_AGG(CONVERT(NVARCHAR(MAX), duplicate_requests.config_id), N', ')
    FROM
    (
        SELECT request_values.config_id
        FROM
        (
            SELECT TRY_CONVERT(INT, JSON_VALUE(request_item.[value], '$.config_id')) AS config_id
            FROM OPENJSON(@run_requests_json) AS request_item
        ) AS request_values
        GROUP BY request_values.config_id
        HAVING COUNT(*) > 1
    ) AS duplicate_requests;

    IF @DuplicateConfigIds IS NOT NULL
    BEGIN
        SET @DuplicateMessage = CONCAT(
            'DUPLICATE_RUN_REQUEST: duplicate config_id(s): ',
            CASE
                WHEN LEN(@DuplicateConfigIds) > 1800
                    THEN CONCAT(LEFT(@DuplicateConfigIds, 1800), ' ...')
                ELSE @DuplicateConfigIds
            END,
            '. Each config_id may appear at most once in p_run_requests.'
        );

        THROW 51013, @DuplicateMessage, 1;
    END;

    RETURN 0;
END;
GO

PRINT 'control.usp_validate_run_requests created successfully.';
GO
