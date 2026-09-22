/*
    04_register_brands_metadata.sql
    Target: Microsoft Fabric SQL Database (sqldb_ecommerce_control)
    Purpose: Register catalog.brands as a new INCREMENTAL source object and
             initialize its watermark state without changing any pipeline code.

    Re-run behavior:
      - Existing brands config is aligned to the expected metadata.
      - Missing brands config is inserted.
      - Existing watermark VALUE is NOT reset.
      - Missing watermark state is initialized to 1900-01-01.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @InitialWatermark DATETIME2(3) = '1900-01-01T00:00:00.000';

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE control.ingestion_config
    SET
        target_folder = 'landing/catalog/brands',
        load_strategy = 'INCREMENTAL',
        watermark_field = 'updated_at',
        is_active = 1,
        updated_at = SYSUTCDATETIME()
    WHERE source_system = 'ECOMMERCE_AZSQL'
      AND source_schema = 'catalog'
      AND source_object = 'brands';

    IF NOT EXISTS
    (
        SELECT 1
        FROM control.ingestion_config
        WHERE source_system = 'ECOMMERCE_AZSQL'
          AND source_schema = 'catalog'
          AND source_object = 'brands'
    )
    BEGIN
        INSERT INTO control.ingestion_config
        (
            source_system,
            source_schema,
            source_object,
            target_folder,
            load_strategy,
            watermark_field,
            is_active
        )
        VALUES
        (
            'ECOMMERCE_AZSQL',
            'catalog',
            'brands',
            'landing/catalog/brands',
            'INCREMENTAL',
            'updated_at',
            1
        );
    END;

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
    WHERE c.source_system = 'ECOMMERCE_AZSQL'
      AND c.source_schema = 'catalog'
      AND c.source_object = 'brands'
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
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT
    ingestion_config_id,
    source_system,
    source_schema,
    source_object,
    target_folder,
    load_strategy,
    watermark_field,
    is_active,
    created_at,
    updated_at
FROM control.ingestion_config
WHERE source_system = 'ECOMMERCE_AZSQL'
  AND source_schema = 'catalog'
  AND source_object = 'brands';

SELECT
    ingestion_config_id,
    source_system,
    source_schema,
    source_object,
    load_strategy,
    watermark_field,
    last_watermark_value,
    last_successful_batch_id,
    last_successful_pipeline_run_id,
    watermark_updated_at
FROM control.v_pipeline_watermarks
WHERE source_system = 'ECOMMERCE_AZSQL'
  AND source_schema = 'catalog'
  AND source_object = 'brands';
GO

PRINT 'catalog.brands metadata registered successfully.';
GO