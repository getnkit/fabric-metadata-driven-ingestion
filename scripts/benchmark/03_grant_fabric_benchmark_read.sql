/*
    Target: Amazon RDS for SQL Server (sql_ingestion_benchmark).
    Run as an administrator with CREATE LOGIN permission after the
    benchmark schema is created. Replace placeholder LOCALLY.
    No Azure SQL contained database user is assumed.
*/
SET NOCOUNT ON;
GO
USE [master];
GO
IF SUSER_ID(N'fabric_benchmark_user') IS NULL
    CREATE LOGIN [fabric_benchmark_user]
        WITH PASSWORD = '<REPLACE_WITH_STRONG_PASSWORD>',
             CHECK_POLICY = ON;
GO
USE [sql_ingestion_benchmark];
GO
IF DATABASE_PRINCIPAL_ID(N'fabric_benchmark_user') IS NULL
    CREATE USER [fabric_benchmark_user] FOR LOGIN [fabric_benchmark_user];
GO
GRANT SELECT ON SCHEMA::[benchmark] TO [fabric_benchmark_user];
GO
PRINT 'fabric_benchmark_user granted read-only SELECT on benchmark schema.';
GO
