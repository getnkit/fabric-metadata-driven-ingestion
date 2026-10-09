

/*
    Validate the top-level explicit run-request envelope before Dispatcher fan-out.

    This procedure validates only request shape and cross-request safety that can be
    decided without loading ingestion_config. Config-specific semantics (for example,
    FULL/INCREMENTAL boundary rules) remain owned by pl_ingest_object_controller.
*/
CREATE   PROCEDURE control.usp_validate_run_requests
    @run_requests_json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(ISJSON(@run_requests_json, ARRAY), 0) <> 1
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

        Optional object fields:
          lower_bound : string or null
          upper_bound : string or null

        Missing bounds are normalized to empty strings by the Dispatcher.
        Config-specific bound semantics remain owned by the Controller.
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
            OR EXISTS
            (
                SELECT 1
                FROM OPENJSON(request_item.[value]) AS property
                WHERE property.[key] IN ('lower_bound', 'upper_bound')
                  AND property.[type] NOT IN (0, 1)
            )
    )
    BEGIN
        THROW 51012, 'INVALID_RUN_REQUESTS: each request requires positive integer config_id and REGULAR/BACKFILL run_type; optional lower_bound/upper_bound must be string or null.', 1;
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

