/*
    03_seed_connection_settings.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Seed logical connection references used by the metadata-driven
             ingestion framework.

    Environment-specific IDs are intentionally not committed.
    Set the variables below before running this script in each environment.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @SourceConnectionId NVARCHAR(100) = NULL;
DECLARE @TargetConnectionId NVARCHAR(100) = NULL;
DECLARE @TargetWorkspaceId  NVARCHAR(100) = NULL;
DECLARE @TargetItemId       NVARCHAR(100) = NULL;

IF @SourceConnectionId IS NULL
   OR @TargetConnectionId IS NULL
   OR @TargetWorkspaceId IS NULL
   OR @TargetItemId IS NULL
BEGIN
    THROW 51010, 'Set SourceConnectionId, TargetConnectionId, TargetWorkspaceId, and TargetItemId before running this seed.', 1;
END;

DECLARE @Seed TABLE
(
    connection_ref       NVARCHAR(100) NOT NULL,
    connection_type      VARCHAR(50) NOT NULL,
    connection_settings  NVARCHAR(MAX) NOT NULL
);

INSERT INTO @Seed
(
    connection_ref,
    connection_type,
    connection_settings
)
VALUES
(
    'AZSQL_ECOMMERCE',
    'SQL_SERVER',
    CONCAT(
        N'{"connectionId":"',
        @SourceConnectionId,
        N'","database":"sql_ecommerce_db"}'
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