/*
    Target: SQL Server 2022 Developer on EC2 (sql_benchmark_db).
    Run as an administrator with CREATE LOGIN permission after the
    benchmark schema is created. Replace placeholder LOCALLY.
    No Azure SQL contained database user is assumed.
*/
SET NOCOUNT ON;
GO
USE [master];
GO
IF SUSER_ID(N'fabric_benchmark_reader') IS NULL
    CREATE LOGIN [fabric_benchmark_reader]
        WITH PASSWORD = '<REPLACE_WITH_STRONG_PASSWORD>',
             CHECK_POLICY = ON;
GO
USE [sql_benchmark_db];
GO
IF DATABASE_PRINCIPAL_ID(N'fabric_benchmark_reader') IS NULL
    CREATE USER [fabric_benchmark_reader] FOR LOGIN [fabric_benchmark_reader];
GO
GRANT SELECT ON SCHEMA::[benchmark] TO [fabric_benchmark_reader];
GO
PRINT 'fabric_benchmark_reader granted read-only SELECT on benchmark schema.';
GO
