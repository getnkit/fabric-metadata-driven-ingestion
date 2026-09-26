/*
    04_seed_ingestion_metadata.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Seed the initial ingestion configuration and initialize watermark state
             for INCREMENTAL source objects.

    Re-run behavior:
      - Existing config rows are updated.
      - Missing config rows are inserted.
      - Existing watermark values are preserved.
      - Missing watermark rows are initialized to 1900-01-01.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @InitialWatermark DATETIME2(3) = '1900-01-01T00:00:00.000';

DECLARE @Seed TABLE
(
    source_system    NVARCHAR(100) NOT NULL,
    source_conn_ref  NVARCHAR(100) NOT NULL,
    source_schema    NVARCHAR(128) NOT NULL,
    source_object    NVARCHAR(128) NOT NULL,
    target_folder    NVARCHAR(500) NOT NULL,
    target_conn_ref  NVARCHAR(100) NOT NULL,
    target_schema    NVARCHAR(128) NOT NULL,
    target_table     NVARCHAR(128) NOT NULL,
    load_strategy    VARCHAR(20) NOT NULL,
    watermark_field  NVARCHAR(128) NULL,
    is_active        BIT NOT NULL
);

INSERT INTO @Seed
(
    source_system,
    source_conn_ref,
    source_schema,
    source_object,
    target_folder,
    target_conn_ref,
    target_schema,
    target_table,
    load_strategy,
    watermark_field,
    is_active
)
VALUES
    ('ECOMMERCE', 'AZSQL_ECOMMERCE', 'crm',     'customers',          'landing/crm/customers',              'LH_ECOMMERCE_BRONZE', 'crm', 'customers',              'INCREMENTAL', 'updated_at', 1),
    ('ECOMMERCE', 'AZSQL_ECOMMERCE', 'partner', 'merchants',          'landing/partner/merchants',          'LH_ECOMMERCE_BRONZE', 'partner', 'merchants',          'INCREMENTAL', 'updated_at', 1),
    ('ECOMMERCE', 'AZSQL_ECOMMERCE', 'catalog', 'product_categories', 'landing/catalog/product_categories', 'LH_ECOMMERCE_BRONZE', 'catalog', 'product_categories', 'FULL',        NULL,         1),
    ('ECOMMERCE', 'AZSQL_ECOMMERCE', 'catalog', 'products',           'landing/catalog/products',           'LH_ECOMMERCE_BRONZE', 'catalog', 'products',           'INCREMENTAL', 'updated_at', 1),
    ('ECOMMERCE', 'AZSQL_ECOMMERCE', 'catalog', 'brands',             'landing/catalog/brands',             'LH_ECOMMERCE_BRONZE', 'catalog', 'brands',             'INCREMENTAL', 'updated_at', 1),
    ('ECOMMERCE', 'AZSQL_ECOMMERCE', 'sales',   'orders',             'landing/sales/orders',               'LH_ECOMMERCE_BRONZE', 'sales', 'orders',               'INCREMENTAL', 'updated_at', 1),
    ('ECOMMERCE', 'AZSQL_ECOMMERCE', 'sales',   'order_items',        'landing/sales/order_items',          'LH_ECOMMERCE_BRONZE', 'sales', 'order_items',          'INCREMENTAL', 'updated_at', 1);

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE control.ingestion_config
    SET
        source_system = 'ECOMMERCE',
        updated_at = SYSUTCDATETIME()
    WHERE source_system = 'ECOMMERCE_AZSQL';

    UPDATE c
    SET
        c.source_conn_ref = s.source_conn_ref,
        c.target_folder = s.target_folder,
        c.target_conn_ref = s.target_conn_ref,
        c.target_schema = s.target_schema,
        c.target_table = s.target_table,
        c.load_strategy = s.load_strategy,
        c.watermark_field = s.watermark_field,
        c.is_active = s.is_active,
        c.updated_at = SYSUTCDATETIME()
    FROM control.ingestion_config c
    JOIN @Seed s
      ON s.source_system = c.source_system
     AND s.source_schema = c.source_schema
     AND s.source_object = c.source_object;

    INSERT INTO control.ingestion_config
    (
        source_system,
        source_conn_ref,
        source_schema,
        source_object,
        target_folder,
        target_conn_ref,
        target_schema,
        target_table,
        load_strategy,
        watermark_field,
        is_active
    )
    SELECT
        s.source_system,
        s.source_conn_ref,
        s.source_schema,
        s.source_object,
        s.target_folder,
        s.target_conn_ref,
        s.target_schema,
        s.target_table,
        s.load_strategy,
        s.watermark_field,
        s.is_active
    FROM @Seed s
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM control.ingestion_config c
        WHERE c.source_system = s.source_system
          AND c.source_schema = s.source_schema
          AND c.source_object = s.source_object
    );

    INSERT INTO control.pipeline_watermarks
    (
        ingestion_config_id,
        watermark_field,
        last_watermark_value
    )
    SELECT
        c.ingestion_config_id,
        c.watermark_field,
        @InitialWatermark
    FROM control.ingestion_config c
    WHERE c.source_system = 'ECOMMERCE'
      AND c.load_strategy = 'INCREMENTAL'
      AND NOT EXISTS
      (
          SELECT 1
          FROM control.pipeline_watermarks w
          WHERE w.ingestion_config_id = c.ingestion_config_id
      );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT
    ingestion_config_id,
    source_system,
    source_conn_ref,
    source_schema,
    source_object,
    target_folder,
    target_conn_ref,
    target_schema,
    target_table,
    load_strategy,
    watermark_field,
    is_active,
    created_at,
    updated_at
FROM control.ingestion_config
WHERE source_system = 'ECOMMERCE'
ORDER BY ingestion_config_id;

SELECT *
FROM control.v_pipeline_watermarks
WHERE source_system = 'ECOMMERCE'
ORDER BY ingestion_config_id;
GO