/*
    03_grant_fabric_benchmark_read.sql
    Target: Azure SQL Database (sql_ingestion_benchmark)
    Purpose: Create the read-only contained database user used by the Fabric
             benchmark Azure SQL connection.

    Replace the placeholder before execution. Never commit the real password.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DATABASE_PRINCIPAL_ID('fabric_benchmark_user') IS NULL
BEGIN
    CREATE USER fabric_benchmark_user
    WITH PASSWORD = 'REPLACE_WITH_STRONG_PASSWORD';
END;
GO

GRANT SELECT ON SCHEMA::benchmark TO fabric_benchmark_user;
GO

PRINT 'fabric_benchmark_user has read-only SELECT access to schema benchmark.';
GO
