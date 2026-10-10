/*
    01_cutover_existing_dev_to_sql_server.sql
    Target: EXISTING Fabric SQL Database [sqldb_ingestion_control] in DEV.
    Run ONLY AFTER creating and testing the generic Fabric SQL Server connection(s).
    Purpose: cut over demo source refs from prior Azure SQL / RDS SQL Server
             to generic SQL Server without recreating ingestion_config rows.

    NOT a fresh-install script. NEVER run against the EC2 source database.
    No source data, watermark rows, audit rows, config IDs or history are reset.
    Review source HIGH/LOW compatibility independently before enabling REGULAR.
    Benchmark database rename on EC2 is a SEPARATE manual SQL Server operation;
    this script only migrates Fabric Control Plane references.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @SourceConnectionId NVARCHAR(100) = NULL;     -- REQUIRED: generic SQL Server connection to sql_ecommerce_db
DECLARE @BenchmarkConnectionId NVARCHAR(100) = NULL;  -- REQUIRED if legacy benchmark ref/system exists
DECLARE @SourceNewRef NVARCHAR(100) = N'SQL_SERVER_ECOMMERCE';
DECLARE @BenchmarkNewRef NVARCHAR(100) = N'SQL_SERVER_BENCHMARK_DB';
DECLARE @BenchmarkNewSystem NVARCHAR(100) = N'BENCHMARK_DB';
DECLARE @NewType VARCHAR(50) = 'SQL_SERVER';

IF NULLIF(TRIM(@SourceConnectionId), N'') IS NULL
    THROW 51300, 'Set SourceConnectionId from the generic Fabric SQL Server connection before cutover.', 1;

IF OBJECT_ID(N'control.connection_settings', N'U') IS NULL
   OR OBJECT_ID(N'control.ingestion_config', N'U') IS NULL
   OR OBJECT_ID(N'control.pipeline_watermarks', N'U') IS NULL
   OR OBJECT_ID(N'audit.ingestion_log', N'U') IS NULL
    THROW 51301, 'Existing Control/Audit tables required; use Starter Kit for fresh installations.', 1;

/* Fail closed: this operation owns only ECOMMERCE and BENCHMARK_DB.
   RDS_INGESTION_BENCHMARK, SQL_SERVER_INGESTION_BENCHMARK and
   INGESTION_BENCHMARK below are HISTORICAL migration input names only.
   Never use them when registering new metadata. */
IF EXISTS
(
    SELECT 1 FROM control.connection_settings
    WHERE connection_type IN ('AZURE_SQL', 'AMAZON_RDS_SQL_SERVER')
      AND connection_ref NOT IN
          ('AZSQL_ECOMMERCE', 'RDS_ECOMMERCE', 'RDS_INGESTION_BENCHMARK')
)
    THROW 51302, 'Other legacy SQL refs exist. Plan their migration separately.', 1;

IF EXISTS
(
    SELECT 1 FROM control.ingestion_config
    WHERE source_conn_ref IN ('AZSQL_ECOMMERCE', 'RDS_ECOMMERCE')
      AND source_system <> 'ECOMMERCE'
)
    THROW 51303, 'A non-ECOMMERCE config uses an ECOMMERCE legacy ref.', 1;

IF EXISTS
(
    SELECT 1 FROM control.ingestion_config
    WHERE source_conn_ref IN
          ('RDS_INGESTION_BENCHMARK', 'SQL_SERVER_INGESTION_BENCHMARK')
      AND source_system NOT IN ('INGESTION_BENCHMARK', 'BENCHMARK_DB')
)
    THROW 51304, 'A non-benchmark config uses the legacy benchmark ref.', 1;

IF EXISTS
(
    SELECT 1 FROM control.connection_settings
    WHERE connection_ref IN (@SourceNewRef, @BenchmarkNewRef)
      AND connection_type <> @NewType
)
    THROW 51305, 'A SQL_SERVER target ref already has another connector type.', 1;

IF EXISTS
(
    SELECT 1 FROM control.ingestion_config
    WHERE (source_conn_ref = @SourceNewRef AND source_system <> 'ECOMMERCE')
       OR (source_conn_ref = @BenchmarkNewRef
           AND source_system NOT IN ('INGESTION_BENCHMARK', 'BENCHMARK_DB'))
)
    THROW 51306, 'A SQL_SERVER target ref is in use by an unrelated source.', 1;

/* Renaming a live logical source requires an explicit new physical connection.
   A prior benchmark source may have been RDS or the generic SQL Server
   connector, and old Config IDs must remain intact. */
IF
(
    EXISTS
    (
        SELECT 1 FROM control.connection_settings
        WHERE connection_ref IN
          ('RDS_INGESTION_BENCHMARK', 'SQL_SERVER_INGESTION_BENCHMARK')
    )
    OR EXISTS
    (
        SELECT 1 FROM control.ingestion_config
        WHERE source_system = 'INGESTION_BENCHMARK'
           OR source_conn_ref IN
              ('RDS_INGESTION_BENCHMARK', 'SQL_SERVER_INGESTION_BENCHMARK')
    )
)
AND NULLIF(TRIM(@BenchmarkConnectionId), N'') IS NULL
    THROW 51307, 'Set BenchmarkConnectionId to migrate old benchmark references.', 1;

/* Protect config identity if both old and new benchmark source names exist. */
IF EXISTS
(
    SELECT 1
    FROM control.ingestion_config old_cfg
    JOIN control.ingestion_config new_cfg
      ON old_cfg.source_schema = new_cfg.source_schema
     AND old_cfg.source_object = new_cfg.source_object
    WHERE old_cfg.source_system = 'INGESTION_BENCHMARK'
      AND new_cfg.source_system = 'BENCHMARK_DB'
)
    THROW 51309, 'Both legacy and current benchmark configs exist for one object. Reconcile before cutover.', 1;

DECLARE @SourceSettings NVARCHAR(MAX) =
    CONCAT(N'{"connectionId":"', STRING_ESCAPE(@SourceConnectionId, 'json'), N'"}');
DECLARE @BenchmarkSettings NVARCHAR(MAX) =
    CASE WHEN NULLIF(TRIM(@BenchmarkConnectionId), N'') IS NULL THEN NULL
         ELSE CONCAT(N'{"connectionId":"', STRING_ESCAPE(@BenchmarkConnectionId, 'json'), N'"}')
    END;

BEGIN TRY
    BEGIN TRANSACTION;

    /* Upgrade the old strict CHECK atomically with the ref updates. */
    IF EXISTS
    (
        SELECT 1 FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'control.connection_settings')
          AND name = N'CK_connection_settings_type'
    )
        ALTER TABLE control.connection_settings DROP CONSTRAINT CK_connection_settings_type;

    UPDATE control.connection_settings
    SET connection_type = @NewType,
        connection_settings = @SourceSettings,
        updated_at = SYSUTCDATETIME()
    WHERE connection_ref = @SourceNewRef;

    IF @@ROWCOUNT = 0
        INSERT INTO control.connection_settings
            (connection_ref, connection_type, connection_settings)
        VALUES (@SourceNewRef, @NewType, @SourceSettings);

    UPDATE control.ingestion_config
    SET source_conn_ref = @SourceNewRef,
        updated_at = SYSUTCDATETIME()
    WHERE source_system = 'ECOMMERCE'
      AND source_conn_ref IN ('AZSQL_ECOMMERCE', 'RDS_ECOMMERCE');

    IF @BenchmarkSettings IS NOT NULL
    BEGIN
        UPDATE control.connection_settings
        SET connection_type = @NewType,
            connection_settings = @BenchmarkSettings,
            updated_at = SYSUTCDATETIME()
        WHERE connection_ref = @BenchmarkNewRef;

        IF @@ROWCOUNT = 0
            INSERT INTO control.connection_settings
                (connection_ref, connection_type, connection_settings)
            VALUES (@BenchmarkNewRef, @NewType, @BenchmarkSettings);

        UPDATE control.ingestion_config
        SET source_conn_ref = @BenchmarkNewRef,
            source_system = @BenchmarkNewSystem,
            updated_at = SYSUTCDATETIME()
        WHERE source_system IN ('INGESTION_BENCHMARK', @BenchmarkNewSystem)
          AND source_conn_ref IN
              ('RDS_INGESTION_BENCHMARK',
               'SQL_SERVER_INGESTION_BENCHMARK',
               @BenchmarkNewRef);
    END;

    IF EXISTS
    (
        SELECT 1 FROM control.ingestion_config
        WHERE source_conn_ref IN
            ('AZSQL_ECOMMERCE', 'RDS_ECOMMERCE',
             'RDS_INGESTION_BENCHMARK', 'SQL_SERVER_INGESTION_BENCHMARK')
           OR source_system = 'INGESTION_BENCHMARK'
    )
        THROW 51308, 'Legacy refs remain in configs; cutover rolled back.', 1;

    DELETE FROM control.connection_settings
    WHERE connection_ref IN
          ('AZSQL_ECOMMERCE', 'RDS_ECOMMERCE',
           'RDS_INGESTION_BENCHMARK', 'SQL_SERVER_INGESTION_BENCHMARK')
      AND NOT EXISTS
      (
          SELECT 1 FROM control.ingestion_config c
          WHERE c.source_conn_ref = control.connection_settings.connection_ref
      );

    ALTER TABLE control.connection_settings WITH CHECK
        ADD CONSTRAINT CK_connection_settings_type
            CHECK (connection_type IN ('SQL_SERVER', 'SFTP', 'LAKEHOUSE'));

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

/* Read-only evidence: NEVER rewrite existing watermark/audit history. */
SELECT connection_ref, connection_type, connection_settings
FROM control.connection_settings ORDER BY connection_ref;

SELECT ingestion_config_id, source_system, source_conn_ref, source_schema,
       source_object, load_strategy, watermark_field
FROM control.ingestion_config
WHERE source_system IN ('ECOMMERCE', 'BENCHMARK_DB')
ORDER BY source_system, ingestion_config_id;

SELECT c.ingestion_config_id, c.source_object, w.watermark_field,
       w.last_watermark_value, w.last_successful_batch_id,
       w.last_successful_pipeline_run_id
FROM control.ingestion_config c
JOIN control.pipeline_watermarks w
  ON w.ingestion_config_id = c.ingestion_config_id
WHERE c.source_system = 'ECOMMERCE'
ORDER BY c.ingestion_config_id;
GO
