/*
    008_add_ingestion_log_source_metadata.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Add nullable source_path and ingestion_pattern to ingestion audit.
    No historical audit rows or watermark state are rewritten.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('audit.ingestion_log', 'U') IS NULL
    THROW 51060, 'MISSING_INGESTION_LOG: audit.ingestion_log does not exist.', 1;

IF COL_LENGTH('audit.ingestion_log', 'source_path') IS NULL
BEGIN
    ALTER TABLE audit.ingestion_log
        ADD source_path NVARCHAR(1000) NULL;
END;

IF COL_LENGTH('audit.ingestion_log', 'ingestion_pattern') IS NULL
BEGIN
    ALTER TABLE audit.ingestion_log
        ADD ingestion_pattern VARCHAR(20) NULL;
END;

PRINT 'Ingestion audit source_path / ingestion_pattern columns are available.';
GO
