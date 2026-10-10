/*
    03_seed_connection_settings.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Seed core logical connections and optionally register one benchmark
             SQL Server source connection without requiring separate script.

    Environment-specific IDs are intentionally not committed.
    Set the variables below before running this script in each environment.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

/* Bind the core DEV connections. To register benchmark only in an existing DEV,
   fill BenchmarkSourceConnectionId and leave ALL five core IDs NULL. */
DECLARE @SourceConnectionId NVARCHAR(100) = NULL;
DECLARE @SftpConnectionId   NVARCHAR(100) = NULL;
DECLARE @TargetConnectionId NVARCHAR(100) = NULL;
DECLARE @TargetWorkspaceId  NVARCHAR(100) = NULL;
DECLARE @TargetItemId       NVARCHAR(100) = NULL;
DECLARE @BenchmarkSourceConnectionId NVARCHAR(100) = NULL; -- optional (SQL Server benchmark DB)

/* All five core IDs are required together; none are required for benchmark-only setup.
   Existing core bindings are never rewritten when only benchmark ID is supplied. */
DECLARE @CoreProvided INT =
    CASE WHEN @SourceConnectionId IS NULL THEN 0 ELSE 1 END
  + CASE WHEN @SftpConnectionId IS NULL THEN 0 ELSE 1 END
  + CASE WHEN @TargetConnectionId IS NULL THEN 0 ELSE 1 END
  + CASE WHEN @TargetWorkspaceId IS NULL THEN 0 ELSE 1 END
  + CASE WHEN @TargetItemId IS NULL THEN 0 ELSE 1 END;

IF @CoreProvided NOT IN (0, 5)
    THROW 51010, 'Supply all five core IDs together, or none for benchmark-only registration.', 1;

IF @CoreProvided = 0 AND @BenchmarkSourceConnectionId IS NULL
    THROW 51011, 'Set all five core IDs or the optional BenchmarkSourceConnectionId.', 1;

IF @BenchmarkSourceConnectionId IS NOT NULL
   AND NULLIF(LTRIM(RTRIM(@BenchmarkSourceConnectionId)), N'') IS NULL
    THROW 51012, 'BenchmarkSourceConnectionId cannot be empty.', 1;

DECLARE @Seed TABLE
(
    connection_ref       NVARCHAR(100) NOT NULL,
    connection_type      VARCHAR(50) NOT NULL,
    connection_settings  NVARCHAR(MAX) NOT NULL
);

IF @CoreProvided = 5
INSERT INTO @Seed
(
    connection_ref,
    connection_type,
    connection_settings
)
VALUES
(
    'SQL_SERVER_ECOMMERCE',
    'SQL_SERVER',
    CONCAT(
        N'{"connectionId":"',
        @SourceConnectionId,
        N'"}'
    )
),
(
    'SFTP_LOGISTICS_VENDOR',
    'SFTP',
    CONCAT(
        N'{"connectionId":"',
        @SftpConnectionId,
        N'"}'
    )
),
(
    'LH_ECOMMERCE_BRONZE',
    'LAKEHOUSE',
    CONCAT(
        N'{"connectionId":"',
        @TargetConnectionId,
        N'","workspaceId":"',
        @TargetWorkspaceId,
        N'","itemId":"',
        @TargetItemId,
        N'"}'
    )
);

/* Optional dedicated benchmark connection; omitted entirely when NULL.
   Register this independently without touching live E-commerce/SFTP/target bindings. */
IF @BenchmarkSourceConnectionId IS NOT NULL
BEGIN
    INSERT INTO @Seed(connection_ref, connection_type, connection_settings)
    VALUES
    (
        'SQL_SERVER_BENCHMARK_DB',
        'SQL_SERVER',
        CONCAT(N'{"connectionId":"', @BenchmarkSourceConnectionId, N'"}')
    );
END;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE c
    SET
        c.connection_type = s.connection_type,
        c.connection_settings = s.connection_settings,
        c.updated_at = SYSUTCDATETIME()
    FROM control.connection_settings c
    JOIN @Seed s
      ON s.connection_ref = c.connection_ref;

    INSERT INTO control.connection_settings
    (
        connection_ref,
        connection_type,
        connection_settings
    )
    SELECT
        s.connection_ref,
        s.connection_type,
        s.connection_settings
    FROM @Seed s
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM control.connection_settings c
        WHERE c.connection_ref = s.connection_ref
    );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT
    connection_ref,
    connection_type,
    connection_settings,
    created_at,
    updated_at
FROM control.connection_settings
ORDER BY connection_ref;
GO