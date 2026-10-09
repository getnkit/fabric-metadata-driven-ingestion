/*
    01_cutover_existing_dev_to_rds.sql
    Target: EXISTING Fabric SQL Database [sqldb_ingestion_control] in DEV.
    Run ONLY AFTER creating/testing Fabric Amazon RDS for SQL Server Connection.
    Purpose: move the existing ECOMMERCE source connection from AZURE_SQL to
    AMAZON_RDS_SQL_SERVER without resetting config IDs, watermark state,
    audit history, or historical run references.

    DO NOT run on the Amazon RDS source database.
    DO NOT use as a fresh-install script or generic PROD migration.

    This is a reviewed one-time operational cutover. It is transactional
    and repeats safely when the RDS logical connection already exists.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @RdsConnectionId NVARCHAR(100) = NULL; -- REQUIRED: Fabric Connection ID
DECLARE @OldRef NVARCHAR(100) = N'AZSQL_ECOMMERCE';
DECLARE @NewRef NVARCHAR(100) = N'RDS_ECOMMERCE';
DECLARE @NewType VARCHAR(50) = 'AMAZON_RDS_SQL_SERVER';

IF NULLIF(TRIM(@RdsConnectionId), N'') IS NULL
    THROW 51300, 'Set RdsConnectionId from the Fabric Amazon RDS for SQL Server Connection before cutover.', 1;

IF OBJECT_ID(N'control.connection_settings', N'U') IS NULL
   OR OBJECT_ID(N'control.ingestion_config', N'U') IS NULL
   OR OBJECT_ID(N'control.pipeline_watermarks', N'U') IS NULL
   OR OBJECT_ID(N'audit.ingestion_log', N'U') IS NULL
    THROW 51301, 'Existing Control/Audit tables are required. Use fresh Starter Kit for a new database.', 1;

/* Fail closed if other legacy Azure SQL logical connections exist.
   They require an individually planned cutover before strict baseline. */
IF EXISTS
(
    SELECT 1 FROM control.connection_settings
    WHERE connection_type = 'AZURE_SQL'
      AND connection_ref <> @OldRef
)
    THROW 51302, 'Other AZURE_SQL connection refs exist. Migrate those explicitly before enforcing the RDS-only baseline.', 1;

/* This script owns only ECOMMERCE demo configs. Any other source using
   the old reference requires manual review, not implicit redirect. */
IF EXISTS
(
    SELECT 1 FROM control.ingestion_config
    WHERE source_conn_ref = @OldRef
      AND source_system <> 'ECOMMERCE'
)
    THROW 51303, 'Non-ECOMMERCE configs reference AZSQL_ECOMMERCE. Review before cutover.', 1;

IF EXISTS
(
    SELECT 1 FROM control.connection_settings
    WHERE connection_ref = @NewRef
      AND connection_type <> @NewType
)
    THROW 51304, 'RDS_ECOMMERCE is already bound to a different connector type.', 1;

DECLARE @Settings NVARCHAR(MAX) =
    CONCAT(N'{"connectionId":"', STRING_ESCAPE(@RdsConnectionId, 'json'), N'"}');

BEGIN TRY
    BEGIN TRANSACTION;

    /* The old deployed CHECK might still accept AZURE_SQL only.
       Replace it transactionally with the current strict baseline
       after migrating/deleting the old logical connection. */
    IF EXISTS
    (
        SELECT 1 FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'control.connection_settings')
          AND name = N'CK_connection_settings_type'
    )
        ALTER TABLE control.connection_settings
        DROP CONSTRAINT CK_connection_settings_type;

    UPDATE control.connection_settings
    SET connection_settings = @Settings,
        connection_type = @NewType,
        updated_at = SYSUTCDATETIME()
    WHERE connection_ref = @NewRef;

    IF @@ROWCOUNT = 0
        INSERT INTO control.connection_settings
        (
            connection_ref,
            connection_type,
            connection_settings
        )
        VALUES (@NewRef, @NewType, @Settings);

    UPDATE control.ingestion_config
    SET source_conn_ref = @NewRef,
        updated_at = SYSUTCDATETIME()
    WHERE source_conn_ref = @OldRef
      AND source_system = 'ECOMMERCE';

    IF EXISTS
    (
        SELECT 1 FROM control.ingestion_config
        WHERE source_conn_ref = @OldRef
    )
        THROW 51305, 'Old connection remains referenced; transaction rolled back.', 1;

    DELETE FROM control.connection_settings
    WHERE connection_ref = @OldRef
      AND NOT EXISTS
      (
          SELECT 1 FROM control.ingestion_config
          WHERE source_conn_ref = @OldRef
      );

    /* Reject any unexpected old or unsupported type.
       WITH CHECK enforces this on all existing rows. */
    ALTER TABLE control.connection_settings WITH CHECK
        ADD CONSTRAINT CK_connection_settings_type
            CHECK (connection_type IN ('AMAZON_RDS_SQL_SERVER','SFTP','LAKEHOUSE'));

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

/* Read-only post-cutover evidence. Existing watermark and audit rows are
   deliberately NOT updated/reset by this script. */
SELECT connection_ref, connection_type, connection_settings
FROM control.connection_settings
ORDER BY connection_ref;

SELECT ingestion_config_id, source_system, source_conn_ref, source_schema,
       source_object, load_strategy, watermark_field
FROM control.ingestion_config
WHERE source_system = 'ECOMMERCE'
ORDER BY ingestion_config_id;

SELECT c.ingestion_config_id, c.source_object, w.watermark_field,
       w.last_watermark_value, w.last_successful_batch_id,
       w.last_successful_pipeline_run_id
FROM control.ingestion_config c
JOIN control.pipeline_watermarks w
  ON w.ingestion_config_id = c.ingestion_config_id
WHERE c.source_system = 'ECOMMERCE'
ORDER BY c.ingestion_config_id;
GO
