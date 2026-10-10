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

/* Fresh DEV: replace the five required NULLs with their Fabric GUIDs in a
   local execution copy. NULL means "not supplied"; never commit DEV GUIDs.
   Benchmark is optional. For benchmark-only registration in an existing DEV,
   supply only the benchmark ID and leave the five core bindings NULL. */
DECLARE @EcommerceSourceConnectionId NVARCHAR(100)   = NULL; -- Required: E-commerce SQL Server connection
DECLARE @LogisticsSftpConnectionId NVARCHAR(100)      = NULL; -- Required: Logistics SFTP connection
DECLARE @BronzeLakehouseConnectionId NVARCHAR(100)    = NULL; -- Required: Bronze Lakehouse connection
DECLARE @BronzeLakehouseWorkspaceId NVARCHAR(100)     = NULL; -- Required: Bronze Lakehouse workspace
DECLARE @BronzeLakehouseItemId NVARCHAR(100)          = NULL; -- Required: Bronze Lakehouse item
DECLARE @BenchmarkSourceConnectionId NVARCHAR(100)   = NULL; -- Optional: Benchmark SQL Server connection

/* Three Connection IDs plus the Lakehouse Workspace/Item IDs form five core bindings.
   All five are required together; none are required for benchmark-only setup.
   Existing core bindings are never rewritten when only benchmark ID is supplied. */
DECLARE @CoreBindingCount INT =
    CASE WHEN @EcommerceSourceConnectionId IS NULL THEN 0 ELSE 1 END
  + CASE WHEN @LogisticsSftpConnectionId IS NULL THEN 0 ELSE 1 END
  + CASE WHEN @BronzeLakehouseConnectionId IS NULL THEN 0 ELSE 1 END
  + CASE WHEN @BronzeLakehouseWorkspaceId IS NULL THEN 0 ELSE 1 END
  + CASE WHEN @BronzeLakehouseItemId IS NULL THEN 0 ELSE 1 END;

IF @CoreBindingCount NOT IN (0, 5)
    THROW 51010, 'Supply all five core IDs together, or none for benchmark-only registration.', 1;

IF @CoreBindingCount = 0 AND @BenchmarkSourceConnectionId IS NULL
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

IF @CoreBindingCount = 5
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
        @EcommerceSourceConnectionId,
        N'"}'
    )
),
(
    'SFTP_LOGISTICS_VENDOR',
    'SFTP',
    CONCAT(
        N'{"connectionId":"',
        @LogisticsSftpConnectionId,
        N'"}'
    )
),
(
    'LH_ECOMMERCE_BRONZE',
    'LAKEHOUSE',
    CONCAT(
        N'{"connectionId":"',
        @BronzeLakehouseConnectionId,
        N'","workspaceId":"',
        @BronzeLakehouseWorkspaceId,
        N'","itemId":"',
        @BronzeLakehouseItemId,
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
        'SQL_SERVER_BENCHMARK',
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