/*
    002_add_sftp_connection.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Enable the SFTP connection type and register the Fabric SFTP connection.

    Before running:
      - Set @SftpConnectionId to the Connection ID of Fabric connection cn_sftp_logistics_vendor.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @SftpConnectionId NVARCHAR(100) = NULL;

IF @SftpConnectionId IS NULL
BEGIN
    THROW 51020, 'Set SftpConnectionId to the Fabric connection ID for cn_sftp_logistics_vendor before running this migration.', 1;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    IF EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE name = 'CK_connection_settings_type'
          AND parent_object_id = OBJECT_ID('control.connection_settings')
    )
    BEGIN
        ALTER TABLE control.connection_settings
        DROP CONSTRAINT CK_connection_settings_type;
    END;

    ALTER TABLE control.connection_settings
    ADD CONSTRAINT CK_connection_settings_type
        CHECK (connection_type IN ('AZURE_SQL','SFTP','LAKEHOUSE'));

    IF EXISTS
    (
        SELECT 1
        FROM control.connection_settings
        WHERE connection_ref = 'SFTP_LOGISTICS_VENDOR'
    )
    BEGIN
        UPDATE control.connection_settings
        SET
            connection_type = 'SFTP',
            connection_settings = CONCAT(
                N'{"connectionId":"',
                @SftpConnectionId,
                N'"}'
            ),
            updated_at = SYSUTCDATETIME()
        WHERE connection_ref = 'SFTP_LOGISTICS_VENDOR';
    END
    ELSE
    BEGIN
        INSERT INTO control.connection_settings
        (
            connection_ref,
            connection_type,
            connection_settings
        )
        VALUES
        (
            'SFTP_LOGISTICS_VENDOR',
            'SFTP',
            CONCAT(
                N'{"connectionId":"',
                @SftpConnectionId,
                N'"}'
            )
        );
    END;

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
WHERE connection_ref = 'SFTP_LOGISTICS_VENDOR';
GO
