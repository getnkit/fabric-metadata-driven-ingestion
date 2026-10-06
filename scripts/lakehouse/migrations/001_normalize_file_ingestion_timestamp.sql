/*
    001_normalize_file_ingestion_timestamp.sql
    Target: Microsoft Fabric Lakehouse (lh_ecommerce_bronze)
    Engine: Spark SQL

    Purpose:
      - Normalize FILE Bronze technical column _ingestion_timestamp from STRING
        to TIMESTAMP for tables created before the notebook cast was introduced.
      - Preserve existing Bronze rows and table identity/history.
      - Keep the migration safe to rerun after a partial or completed execution.

    Run this in a Fabric Notebook SQL cell (Spark SQL) with lh_ecommerce_bronze
    attached as the default Lakehouse. Do not run it against the Lakehouse SQL
    analytics endpoint.

    A direct ALTER COLUMN is not used because STRING -> TIMESTAMP is not a Delta
    type-widening conversion. CREATE OR REPLACE TABLE rewrites the table with the
    desired schema while preserving the table identity.
*/

/* FILE/FULL: fulfillment.inventory_snapshots */
CREATE OR REPLACE TABLE fulfillment.__mig001_inventory_snapshots
USING DELTA
AS
SELECT
    warehouse_code,
    sku,
    on_hand_qty,
    reserved_qty,
    available_qty,
    inventory_status,
    snapshot_at,
    _batch_id,
    _pipeline_run_id,
    CAST(_ingestion_timestamp AS TIMESTAMP) AS _ingestion_timestamp,
    _source_file_name,
    _source_file_path
FROM fulfillment.inventory_snapshots;

CREATE OR REPLACE TABLE fulfillment.inventory_snapshots
USING DELTA
AS
SELECT *
FROM fulfillment.__mig001_inventory_snapshots;

DROP TABLE IF EXISTS fulfillment.__mig001_inventory_snapshots;


/* FILE/INCREMENTAL: fulfillment.inventory_movements */
CREATE OR REPLACE TABLE fulfillment.__mig001_inventory_movements
USING DELTA
AS
SELECT
    movement_id,
    warehouse_code,
    sku,
    movement_type,
    quantity_change,
    occurred_at,
    _batch_id,
    _pipeline_run_id,
    CAST(_ingestion_timestamp AS TIMESTAMP) AS _ingestion_timestamp,
    _source_file_name,
    _source_file_path
FROM fulfillment.inventory_movements;

CREATE OR REPLACE TABLE fulfillment.inventory_movements
USING DELTA
AS
SELECT *
FROM fulfillment.__mig001_inventory_movements;

DROP TABLE IF EXISTS fulfillment.__mig001_inventory_movements;


/* Verification: _ingestion_timestamp should now be timestamp in both tables. */
DESCRIBE TABLE fulfillment.inventory_snapshots;
DESCRIBE TABLE fulfillment.inventory_movements;
