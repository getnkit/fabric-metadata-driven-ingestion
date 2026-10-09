/*
    009_normalize_file_landing_path.sql
    Target: existing Fabric SQL Database (sqldb_ingestion_control)
    Purpose: align existing Personal FILE metadata to the strict Landing contract.

    control.ingestion_config.landing_path:
      VALID:   landing/logistics_vendor/inventory_snapshot/
      INVALID: Files/landing/logistics_vendor/inventory_snapshot/

    The Lakehouse Files/ root is supplied by Fabric Copy / the Notebook,
    not stored in metadata. This migration changes only the two seeded FILE
    source objects when their old exact paths are present.
    Existing audit history, physical Landing files and watermark state are untouched.

    IMPORTANT: Sync the FULL + INCREMENTAL SFTP adapter definitions and apply this
    migration before running new FILE ingestions. Other custom FILE paths must be
    corrected explicitly; this script never globally replaces nested 'Files/'.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE control.ingestion_config
    SET landing_path = N'landing/logistics_vendor/inventory_snapshot/',
        updated_at = SYSUTCDATETIME()
    WHERE ingestion_pattern = 'FILE'
      AND source_system = 'LOGISTICS_VENDOR'
      AND source_object = 'inventory_snapshot'
      AND landing_path = N'Files/landing/logistics_vendor/inventory_snapshot/';

    UPDATE control.ingestion_config
    SET landing_path = N'landing/logistics_vendor/inventory_movement/',
        updated_at = SYSUTCDATETIME()
    WHERE ingestion_pattern = 'FILE'
      AND source_system = 'LOGISTICS_VENDOR'
      AND source_object = 'inventory_movement'
      AND landing_path = N'Files/landing/logistics_vendor/inventory_movement/';

    -- Reject unreviewed FILE metadata rather than silently rewriting the path.
    IF EXISTS
    (
        SELECT 1
        FROM control.ingestion_config
        WHERE ingestion_pattern = 'FILE'
          AND (
              landing_path IS NULL
              OR LEN(landing_path) <= 8
              OR LEFT(landing_path, 8) COLLATE Latin1_General_100_BIN2 <> N'landing/'
          )
    )
        THROW 51009, 'INVALID_FILE_LANDING_PATH: correct all FILE landing_path values to landing/... (no Files/ prefix) before retrying this migration.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

SELECT ingestion_config_id, source_system, source_object, landing_path
FROM control.ingestion_config
WHERE ingestion_pattern = 'FILE'
ORDER BY source_system, source_object;
GO
