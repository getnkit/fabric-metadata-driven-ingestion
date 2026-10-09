/*
    010_require_nonblank_file_landing_path.sql
    Target: existing Microsoft Fabric SQL Database (sqldb_ingestion_control)

    Strengthens CK_ingestion_config_landing_path:
      - FILE: landing_path must be non-NULL and nonblank after TRIM.
      - DATABASE / API: existing behavior is unchanged.

    Does not normalize paths, enforce a landing/ prefix, or modify metadata,
    watermark state, audit history, or files in OneLake.
    Safe to rerun: existing check constraint is replaced transactionally.

    If existing FILE records have NULL, empty, or spaces-only landing_path,
    fix them explicitly before rerunning this migration.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF EXISTS
    (
        SELECT 1
        FROM control.ingestion_config
        WHERE ingestion_pattern = 'FILE'
          AND
          (
              landing_path IS NULL
              OR TRIM(landing_path) = N''
          )
    )
        THROW 51010, 'INVALID_FILE_LANDING_PATH: FILE landing_path must not be NULL, empty, or spaces-only. Correct existing metadata before applying this constraint.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE name = 'CK_ingestion_config_landing_path'
          AND parent_object_id = OBJECT_ID(N'control.ingestion_config')
    )
    BEGIN
        ALTER TABLE control.ingestion_config
        DROP CONSTRAINT CK_ingestion_config_landing_path;
    END;

    ALTER TABLE control.ingestion_config WITH CHECK
    ADD CONSTRAINT CK_ingestion_config_landing_path
    CHECK
    (
        ingestion_pattern <> 'FILE'
        OR
        (
            landing_path IS NOT NULL
            AND TRIM(landing_path) <> ''
        )
    );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

SELECT
    name,
    is_disabled,
    is_not_trusted,
    definition
FROM sys.check_constraints
WHERE name = 'CK_ingestion_config_landing_path'
  AND parent_object_id = OBJECT_ID(N'control.ingestion_config');
GO
