/*
    04_add_brands_source.sql
    Target: Azure SQL Database (mock operational source)
    Purpose: Add a new incremental source object to demonstrate
             metadata-driven source onboarding.

    Re-run behavior:
      - Creates catalog.brands only if it does not already exist.
      - Inserts only missing sample brands.
      - Existing rows are not overwritten.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF SCHEMA_ID('catalog') IS NULL
    EXEC('CREATE SCHEMA catalog');
GO

IF OBJECT_ID('catalog.brands', 'U') IS NULL
BEGIN
    CREATE TABLE catalog.brands
    (
        brand_id      INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_brands PRIMARY KEY,
        brand_code    VARCHAR(30) NOT NULL,
        brand_name    NVARCHAR(150) NOT NULL,
        brand_status  VARCHAR(20) NOT NULL,
        created_at    DATETIME2(3) NOT NULL,
        updated_at    DATETIME2(3) NOT NULL,

        CONSTRAINT UQ_brands_code UNIQUE (brand_code),
        CONSTRAINT CK_brands_status
            CHECK (brand_status IN ('ACTIVE','INACTIVE')),
        CONSTRAINT CK_brands_timestamp
            CHECK (updated_at >= created_at)
    );

    CREATE INDEX IX_brands_updated_at
        ON catalog.brands(updated_at, brand_id);
END;
GO

DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();

INSERT INTO catalog.brands
(
    brand_code,
    brand_name,
    brand_status,
    created_at,
    updated_at
)
SELECT
    v.brand_code,
    v.brand_name,
    v.brand_status,
    @Now,
    @Now
FROM
(
    VALUES
        ('BRD-001', N'Apex',   'ACTIVE'),
        ('BRD-002', N'Nova',   'ACTIVE'),
        ('BRD-003', N'Vertex', 'ACTIVE')
) v(brand_code, brand_name, brand_status)
WHERE NOT EXISTS
(
    SELECT 1
    FROM catalog.brands b
    WHERE b.brand_code = v.brand_code
);

SELECT
    brand_id,
    brand_code,
    brand_name,
    brand_status,
    created_at,
    updated_at
FROM catalog.brands
ORDER BY brand_id;
GO

PRINT 'catalog.brands source object created/seeded successfully.';
GO