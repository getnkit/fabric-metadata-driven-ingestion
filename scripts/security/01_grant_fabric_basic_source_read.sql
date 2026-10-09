/*
    Target: Amazon RDS for SQL Server; run on the RDS instance as an
            administrator with CREATE LOGIN permission.
    Run after creating database [sql_ecommerce_db] and source schemas.
    Fabric Amazon RDS for SQL Server connector uses Basic (SQL login).
    Replace the password placeholder LOCALLY, never commit credentials.
    Running again does not change an existing login password; rotate
    explicitly in SQL Server and Fabric Connection when necessary.
*/
SET NOCOUNT ON;
GO
USE [master];
GO
IF SUSER_ID(N'fabric_ingestion_user') IS NULL
BEGIN
    CREATE LOGIN [fabric_ingestion_user]
        WITH PASSWORD = '<REPLACE_WITH_STRONG_PASSWORD>',
             CHECK_POLICY = ON;
END;
GO
USE [sql_ecommerce_db];
GO
IF NOT EXISTS
(
    SELECT 1 FROM sys.database_principals
    WHERE name = N'fabric_ingestion_reader' AND type = 'R'
)
    CREATE ROLE [fabric_ingestion_reader];
GO
GRANT SELECT ON SCHEMA::[crm]     TO [fabric_ingestion_reader];
GRANT SELECT ON SCHEMA::[partner] TO [fabric_ingestion_reader];
GRANT SELECT ON SCHEMA::[catalog] TO [fabric_ingestion_reader];
GRANT SELECT ON SCHEMA::[sales]   TO [fabric_ingestion_reader];
GO
IF DATABASE_PRINCIPAL_ID(N'fabric_ingestion_user') IS NULL
    CREATE USER [fabric_ingestion_user] FOR LOGIN [fabric_ingestion_user];
GO
IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = N'fabric_ingestion_reader'
      AND m.name = N'fabric_ingestion_user'
)
    ALTER ROLE [fabric_ingestion_reader] ADD MEMBER [fabric_ingestion_user];
GO
SELECT m.name AS user_name, r.name AS role_name
FROM sys.database_role_members drm
JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
WHERE r.name = N'fabric_ingestion_reader';
GO
/*
    Fabric Connection: Amazon RDS for SQL Server
    Connection name: cn_src_rds_sql_server
    Server: <RDS endpoint>, port 1433
    Database: sql_ecommerce_db
    Authentication: Basic
    Username: fabric_ingestion_user
    Password: <locally configured password>
    Secure connectivity: restrict source IPs / use private gateway & TLS.
*/
