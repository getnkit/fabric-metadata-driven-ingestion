/*
    005_rename_ingestion_log_target_path.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)

    Purpose:
      - Rename audit.ingestion_log.target_path to landing_path.
      - Preserve all existing audit history.
      - Align the audit field name with its actual semantics: the resolved
        Landing Zone path used by a FILE ingestion run.

    Re-run behavior:
      - Safe to rerun after the rename has already been applied.
      - Fails if both columns exist or neither column exists, because that
        indicates an unexpected schema state.

    Run this migration before syncing the updated stored procedure/pipelines
    from Git. Do not run ingestion pipelines between the migration and Git sync.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('audit.ingestion_log', 'U') IS NULL
    THROW 51040, 'MISSING_AUDIT_SCHEMA: audit.ingestion_log does not exist.', 1;

DECLARE @HasTargetPath BIT =
    CASE WHEN COL_LENGTH('audit.ingestion_log', 'target_path') IS NOT NULL THEN 1 ELSE 0 END;

DECLARE @HasLandingPath BIT =
    CASE WHEN COL_LENGTH('audit.ingestion_log', 'landing_path') IS NOT NULL THEN 1 ELSE 0 END;

IF @HasTargetPath = 1 AND @HasLandingPath = 0
BEGIN
    EXEC sys.sp_rename
        @objname = N'audit.ingestion_log.target_path',
        @newname = N'landing_path',
        @objtype = N'COLUMN';

    PRINT 'Renamed audit.ingestion_log.target_path to landing_path.';
END
ELSE IF @HasTargetPath = 0 AND @HasLandingPath = 1
BEGIN
    PRINT 'Migration already applied: audit.ingestion_log.landing_path exists.';
END
ELSE IF @HasTargetPath = 1 AND @HasLandingPath = 1
BEGIN
    THROW 51041, 'AMBIGUOUS_AUDIT_SCHEMA: both target_path and landing_path exist.', 1;
END
ELSE
BEGIN
    THROW 51042, 'INVALID_AUDIT_SCHEMA: neither target_path nor landing_path exists.', 1;
END;
GO
