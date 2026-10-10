/*
    04_seed_ingestion_metadata.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Seed ingestion configuration and initialize generic pipeline watermark
             state for all INCREMENTAL source objects. DATABASE, FILE, and future
             API patterns share control.pipeline_watermarks.
              FILE landing_path is Lakehouse Files-relative (landing/...; no Files/ prefix).

             sales.order_items demonstrates metadata-driven SQL Server
             DYNAMIC_RANGE partitioning. parallel_copies is intentionally omitted
             so Fabric keeps service-managed parallelism by default.

    Benchmark configs are optional: inserted (INACTIVE) only when the dedicated
    SQL Server benchmark connection reference exists. Existing benchmark configs
    are NEVER updated by this seed, protecting active scenario settings.

    Fresh DEV demo seed ONLY (not generic PROD configuration).
    Re-run behavior:
      - Existing sample config rows are upserted (review before re-running).
      - Existing pipeline_watermarks records are NEVER updated/reset.
      - Only missing DATABASE/FILE incremental state rows are initialized
        at 1900-01-01T00:00:00.000; unimplemented API is not auto-seeded.
      - Metadata Watermark Field changes are NOT silently reconciled to
        persisted checkpoint fields; the adapter intentionally fails mismatch.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @InitialDatabaseWatermark NVARCHAR(1000) = '1900-01-01T00:00:00.000';
DECLARE @InitialFileWatermark NVARCHAR(1000) = '1900-01-01T00:00:00.000';

DECLARE @Seed TABLE
(
    source_system    NVARCHAR(100) NOT NULL,
    source_conn_ref  NVARCHAR(100) NOT NULL,
    source_schema    NVARCHAR(128) NULL,
    source_object    NVARCHAR(128) NOT NULL,
    source_path      NVARCHAR(1000) NULL,
    ingestion_pattern VARCHAR(20) NOT NULL,
    file_format       VARCHAR(30) NULL,
    source_options     NVARCHAR(MAX) NULL,
    copy_options       NVARCHAR(MAX) NULL,
    landing_path    NVARCHAR(1000) NULL,
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
    source_path,
    ingestion_pattern,
    file_format,
    source_options,
    copy_options,
    landing_path,
    target_conn_ref,
    target_schema,
    target_table,
    load_strategy,
    watermark_field,
    is_active
)
VALUES
    ('ECOMMERCE', 'SQL_SERVER_ECOMMERCE', 'crm',     'customers',          NULL, 'DATABASE', NULL, NULL, NULL, NULL, 'LH_ECOMMERCE_BRONZE', 'crm',     'customers',          'INCREMENTAL', 'updated_at', 1),
    ('ECOMMERCE', 'SQL_SERVER_ECOMMERCE', 'partner', 'merchants',          NULL, 'DATABASE', NULL, NULL, NULL, NULL, 'LH_ECOMMERCE_BRONZE', 'partner', 'merchants',          'INCREMENTAL', 'updated_at', 1),
    ('ECOMMERCE', 'SQL_SERVER_ECOMMERCE', 'catalog', 'product_categories', NULL, 'DATABASE', NULL, NULL, NULL, NULL, 'LH_ECOMMERCE_BRONZE', 'catalog', 'product_categories', 'FULL',        NULL,         1),
    ('ECOMMERCE', 'SQL_SERVER_ECOMMERCE', 'catalog', 'products',           NULL, 'DATABASE', NULL, NULL, NULL, NULL, 'LH_ECOMMERCE_BRONZE', 'catalog', 'products',           'INCREMENTAL', 'updated_at', 1),
    ('ECOMMERCE', 'SQL_SERVER_ECOMMERCE', 'sales',   'orders',             NULL, 'DATABASE', NULL, NULL, NULL, NULL, 'LH_ECOMMERCE_BRONZE', 'sales',   'orders',             'INCREMENTAL', 'updated_at', 1),
    ('ECOMMERCE', 'SQL_SERVER_ECOMMERCE', 'sales',   'order_items',        NULL, 'DATABASE', NULL, NULL, N'{"partition_option":"DYNAMIC_RANGE","partition_column":"order_item_id"}', NULL, 'LH_ECOMMERCE_BRONZE', 'sales',   'order_items',        'INCREMENTAL', 'updated_at', 1),
    (
        'LOGISTICS_VENDOR',
        'SFTP_LOGISTICS_VENDOR',
        NULL,
        'inventory_snapshot',
        '/outbound/inventory/',
        'FILE',
        'DELIMITED_TEXT',
        N'{"file_name_pattern":"inventory_snapshot.csv","delimiter":",","has_header":true,"encoding":"UTF-8","quote":"\"","escape":"\\"}',
        NULL,
        'landing/logistics_vendor/inventory_snapshot/',
        'LH_ECOMMERCE_BRONZE',
        'fulfillment',
        'inventory_snapshots',
        'FULL',
        NULL,
        1
    ),
    (
        'LOGISTICS_VENDOR',
        'SFTP_LOGISTICS_VENDOR',
        NULL,
        'inventory_movement',
        '/outbound/inventory/movements/',
        'FILE',
        'DELIMITED_TEXT',
        N'{"file_name_pattern":"inventory_movement_*.csv","delimiter":",","has_header":true,"encoding":"UTF-8","quote":"\"","escape":"\\"}',
        NULL,
        'landing/logistics_vendor/inventory_movement/',
        'LH_ECOMMERCE_BRONZE',
        'fulfillment',
        'inventory_movements',
        'INCREMENTAL',
        'last_modified_time',
        1
    );

/* Optional benchmark metadata belongs in the same ingestion-config seed.
   Existing scenario configs are NOT overwritten, even when this seed is rerun. */
IF EXISTS
(
    SELECT 1
    FROM control.connection_settings
    WHERE connection_ref = 'SQL_SERVER_INGESTION_BENCHMARK'
      AND connection_type = 'SQL_SERVER'
)
BEGIN
    INSERT INTO @Seed
    (
        source_system, source_conn_ref, source_schema, source_object, source_path,
        ingestion_pattern, file_format, source_options, copy_options, landing_path,
        target_conn_ref, target_schema, target_table, load_strategy,
        watermark_field, is_active
    )
    VALUES
    (
        'INGESTION_BENCHMARK', 'SQL_SERVER_INGESTION_BENCHMARK', 'benchmark',
        'copy_source_unpartitioned', NULL, 'DATABASE', NULL, NULL,
        N'{"partition_option":"NONE"}', NULL,
        'LH_ECOMMERCE_BRONZE', 'benchmark', 'copy_benchmark_unpartitioned_none',
        'FULL', NULL, 0
    ),
    (
        'INGESTION_BENCHMARK', 'SQL_SERVER_INGESTION_BENCHMARK', 'benchmark',
        'copy_source_partitioned', NULL, 'DATABASE', NULL, NULL,
        N'{"partition_option":"PHYSICAL_PARTITIONS"}', NULL,
        'LH_ECOMMERCE_BRONZE', 'benchmark', 'copy_benchmark_partitioned_physical',
        'FULL', NULL, 0
    );
END;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE c
    SET
        c.source_conn_ref = s.source_conn_ref,
        c.source_path = s.source_path,
        c.ingestion_pattern = s.ingestion_pattern,
        c.file_format = s.file_format,
        c.source_options = s.source_options,
        c.copy_options = s.copy_options,
        c.landing_path = s.landing_path,
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
     AND
     (
         s.source_schema = c.source_schema
         OR (s.source_schema IS NULL AND c.source_schema IS NULL)
     )
     AND s.source_object = c.source_object
    WHERE s.source_system <> 'INGESTION_BENCHMARK';

    INSERT INTO control.ingestion_config
    (
        source_system,
        source_conn_ref,
        source_schema,
        source_object,
        source_path,
        ingestion_pattern,
        file_format,
        source_options,
        copy_options,
        landing_path,
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
        s.source_path,
        s.ingestion_pattern,
        s.file_format,
        s.source_options,
        s.copy_options,
        s.landing_path,
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
          AND
          (
              c.source_schema = s.source_schema
              OR (c.source_schema IS NULL AND s.source_schema IS NULL)
          )
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
        CASE
            WHEN c.ingestion_pattern = 'DATABASE' THEN @InitialDatabaseWatermark
            WHEN c.ingestion_pattern = 'FILE' THEN @InitialFileWatermark
        END
    FROM control.ingestion_config c
    WHERE c.load_strategy = 'INCREMENTAL'
      AND c.ingestion_pattern IN ('DATABASE','FILE')
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
    source_path,
    ingestion_pattern,
    file_format,
    source_options,
    copy_options,
    landing_path,
    target_conn_ref,
    target_schema,
    target_table,
    load_strategy,
    watermark_field,
    is_active,
    created_at,
    updated_at
FROM control.ingestion_config
WHERE source_system IN ('ECOMMERCE','LOGISTICS_VENDOR','INGESTION_BENCHMARK')
ORDER BY ingestion_config_id;

SELECT *
FROM control.v_pipeline_watermarks
WHERE source_system IN ('ECOMMERCE','LOGISTICS_VENDOR')
ORDER BY ingestion_config_id;
GO