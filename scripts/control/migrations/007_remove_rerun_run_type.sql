/*
  Retire framework-level RERUN from audit.ingestion_log.

  Current framework run types:
    REGULAR
    BACKFILL

  Historical RERUN rows are not rewritten automatically because mapping them to
  REGULAR or BACKFILL would change audit meaning. Review them explicitly first.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('audit.ingestion_log', 'U') IS NULL
    THROW 51000, 'audit.ingestion_log does not exist.', 1;

IF EXISTS
(
    SELECT 1
    FROM audit.ingestion_log
    WHERE run_type = 'RERUN'
)
    THROW 51001, 'Legacy RERUN audit rows exist. Review or archive them explicitly before applying migration 007.', 1;

BEGIN TRANSACTION;

IF EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_ingestion_log_run_type'
      AND parent_object_id = OBJECT_ID('audit.ingestion_log')
)
    ALTER TABLE audit.ingestion_log
        DROP CONSTRAINT CK_ingestion_log_run_type;

ALTER TABLE audit.ingestion_log WITH CHECK
    ADD CONSTRAINT CK_ingestion_log_run_type
        CHECK (run_type IN ('REGULAR','BACKFILL'));

ALTER TABLE audit.ingestion_log
    CHECK CONSTRAINT CK_ingestion_log_run_type;

COMMIT TRANSACTION;
