/*
    06_add_connection_type_constraint.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Enforce the canonical connection types currently supported by the
             ingestion framework without rebuilding the control schema.

    Add new values here only when the corresponding connector implementation
    and ingestion route are supported by the framework.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF EXISTS
(
    SELECT 1
    FROM control.connection_settings
    WHERE connection_type NOT IN ('AZURE_SQL','LAKEHOUSE')
)
BEGIN
    SELECT
        connection_ref,
        connection_type
    FROM control.connection_settings
    WHERE connection_type NOT IN ('AZURE_SQL','LAKEHOUSE')
    ORDER BY connection_ref;

    THROW 51020,
          'Unsupported connection_type values exist. Normalize them before adding CK_connection_settings_type.',
          1;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_connection_settings_type'
      AND parent_object_id = OBJECT_ID('control.connection_settings')
)
BEGIN
    ALTER TABLE control.connection_settings WITH CHECK
    ADD CONSTRAINT CK_connection_settings_type
        CHECK (connection_type IN ('AZURE_SQL','LAKEHOUSE'));

    ALTER TABLE control.connection_settings
        CHECK CONSTRAINT CK_connection_settings_type;
END;
GO

PRINT 'Connection type constraint applied successfully.';
GO
