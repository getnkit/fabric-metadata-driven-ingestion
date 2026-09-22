/*
    01_grant_fabric_basic_source_read.sql
    Target: Azure SQL Database (sql_ecommerce_db)
    Purpose: Create a least-privilege contained database user for Microsoft Fabric
             and grant read-only access to the operational source schemas.

    Authentication:
      - Basic authentication is used because the Fabric workspace and Azure SQL
        source are hosted in different Microsoft Entra tenants.
      - Fabric Workspace Identity is the preferred secretless authentication
        pattern when both services are hosted in the same Microsoft Entra tenant.

    Security notes:
      - Grant SELECT only on crm, partner, catalog, and sales schemas.
      - Replace REPLACE_WITH_STRONG_PASSWORD before execution.
      - Do not commit the real password to Git.
*/

SET NOCOUNT ON;
GO

/* Least-privilege role */
IF NOT EXISTS (
    SELECT 1 FROM sys.database_principals
    WHERE name = N'fabric_ingestion_reader'
      AND type = 'R'
)
BEGIN
    CREATE ROLE [fabric_ingestion_reader];
END;
GO

GRANT SELECT ON SCHEMA::[crm]     TO [fabric_ingestion_reader];
GRANT SELECT ON SCHEMA::[partner] TO [fabric_ingestion_reader];
GRANT SELECT ON SCHEMA::[catalog] TO [fabric_ingestion_reader];
GRANT SELECT ON SCHEMA::[sales]   TO [fabric_ingestion_reader];
GO

/* Contained SQL user used by Fabric Basic authentication */
IF NOT EXISTS (
    SELECT 1 FROM sys.database_principals
    WHERE name = N'fabric_ingestion_user'
)
BEGIN
    CREATE USER [fabric_ingestion_user]
    WITH PASSWORD = '<REPLACE_WITH_STRONG_PASSWORD>';
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    JOIN sys.database_principals r
      ON drm.role_principal_id = r.principal_id
    JOIN sys.database_principals m
      ON drm.member_principal_id = m.principal_id
    WHERE r.name = N'fabric_ingestion_reader'
      AND m.name = N'fabric_ingestion_user'
)
BEGIN
    ALTER ROLE [fabric_ingestion_reader]
    ADD MEMBER [fabric_ingestion_user];
END;
GO

/* Verification */
SELECT
    'PRINCIPAL' AS check_type,
    p.name AS principal_name,
    p.type_desc COLLATE DATABASE_DEFAULT AS detail
FROM sys.database_principals p
WHERE p.name IN (N'fabric_ingestion_user', N'fabric_ingestion_reader')

UNION ALL

SELECT
    'ROLE_MEMBERSHIP',
    m.name,
    CONCAT('Member of ', r.name) COLLATE DATABASE_DEFAULT
FROM sys.database_role_members drm
JOIN sys.database_principals r
  ON drm.role_principal_id = r.principal_id
JOIN sys.database_principals m
  ON drm.member_principal_id = m.principal_id
WHERE r.name = N'fabric_ingestion_reader'
  AND m.name = N'fabric_ingestion_user';
GO

/*
    Fabric connection:
    Connection name : cn_src_azsql
    Server          : sql-srv-ecommerce-db.database.windows.net
    Database        : sql_ecommerce_db
    Authentication  : Basic
    Username        : fabric_ingestion_user
    Password        : <password set above>
*/