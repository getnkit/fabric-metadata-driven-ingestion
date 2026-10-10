/*
    DEV ONLY — DESTRUCTIVE
    Target: sqldb_ingestion_control

    Reset Framework-owned Control/Audit objects for a fresh DEV install.
    Deletes all connection settings, ingestion configs, watermarks, and audit history.
    Keep the control and audit schemas. Stop ingestion runs before executing.
*/

SET NOCOUNT ON;
GO

DROP PROCEDURE IF EXISTS control.usp_finalize_ingestion_run;
DROP PROCEDURE IF EXISTS control.usp_validate_run_requests;
GO

DROP VIEW IF EXISTS control.v_pipeline_watermarks;
GO

-- Drop child tables before parent tables.
DROP TABLE IF EXISTS audit.ingestion_log;
DROP TABLE IF EXISTS control.pipeline_watermarks;
DROP TABLE IF EXISTS control.ingestion_config;
DROP TABLE IF EXISTS control.connection_settings;
GO

-- Expected: no remaining framework tables/views/procedures in these schemas.
SELECT
    s.name AS schema_name,
    o.name AS object_name,
    o.type_desc
FROM sys.objects AS o
JOIN sys.schemas AS s
    ON o.schema_id = s.schema_id
WHERE s.name IN ('control', 'audit')
  AND o.type IN ('U', 'V', 'P')
ORDER BY s.name, o.name;
GO
