/*
    05_register_benchmark_metadata.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Register the benchmark connection and its two INACTIVE source configs.

    Create Fabric connection cn_src_sql_server_ingestion_benchmark first, then paste its
    environment-specific connection ID below. Do not commit the real ID.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @BenchmarkSourceConnectionId NVARCHAR(100) = NULL;

IF @BenchmarkSourceConnectionId IS NULL
BEGIN
    THROW 51120, 'Set BenchmarkSourceConnectionId before running this script.', 1;
END;

DECLARE @ConnectionSettings NVARCHAR(MAX) =
    CONCAT(
        N'{"connectionId":"',
        @BenchmarkSourceConnectionId,
        N'"}'
    );

IF EXISTS
(
    SELECT 1
    FROM control.connection_settings
    WHERE connection_ref = 'SQL_SERVER_INGESTION_BENCHMARK'
)
BEGIN
    UPDATE control.connection_settings
    SET
        connection_type = 'SQL_SERVER',
        connection_settings = @ConnectionSettings,
        updated_at = SYSUTCDATETIME()
    WHERE connection_ref = 'SQL_SERVER_INGESTION_BENCHMARK';
END
ELSE
BEGIN
    INSERT INTO control.connection_settings
    (
        connection_ref,
        connection_type,
        connection_settings
    )
    VALUES
    (
        'SQL_SERVER_INGESTION_BENCHMARK',
        'SQL_SERVER',
        @ConnectionSettings
    );
END;

SELECT *
FROM control.connection_settings
WHERE connection_ref = 'SQL_SERVER_INGESTION_BENCHMARK';

/* Both benchmark configs remain inactive by default. */
IF NOT EXISTS
(
    SELECT 1
    FROM control.connection_settings
    WHERE connection_ref = 'SQL_SERVER_INGESTION_BENCHMARK'
)
BEGIN
    THROW 51130, 'Benchmark connection reference is missing.', 1;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM control.connection_settings
    WHERE connection_ref = 'LH_ECOMMERCE_BRONZE'
)
BEGIN
    THROW 51131, 'Target connection LH_ECOMMERCE_BRONZE does not exist.', 1;
END;

DECLARE @Seed TABLE
(
    source_object  NVARCHAR(128) NOT NULL,
    copy_options   NVARCHAR(MAX) NOT NULL,
    target_table   NVARCHAR(128) NOT NULL
);

INSERT INTO @Seed(source_object, copy_options, target_table)
VALUES
(
    'copy_source_unpartitioned',
    N'{"partition_option":"NONE"}',
    'copy_benchmark_unpartitioned_none'
),
(
    'copy_source_partitioned',
    N'{"partition_option":"PHYSICAL_PARTITIONS"}',
    'copy_benchmark_partitioned_physical'
);

UPDATE c
SET
    c.source_conn_ref = 'SQL_SERVER_INGESTION_BENCHMARK',
    c.source_path = NULL,
    c.ingestion_pattern = 'DATABASE',
    c.file_format = NULL,
    c.source_options = NULL,
    c.copy_options = s.copy_options,
    c.landing_path = NULL,
    c.target_conn_ref = 'LH_ECOMMERCE_BRONZE',
    c.target_schema = 'benchmark',
    c.target_table = s.target_table,
    c.load_strategy = 'FULL',
    c.watermark_field = NULL,
    c.is_active = 0,
    c.updated_at = SYSUTCDATETIME()
FROM control.ingestion_config c
JOIN @Seed s
    ON s.source_object = c.source_object
WHERE c.source_system = 'INGESTION_BENCHMARK'
  AND c.source_schema = 'benchmark';

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
    'INGESTION_BENCHMARK',
    'SQL_SERVER_INGESTION_BENCHMARK',
    'benchmark',
    s.source_object,
    NULL,
    'DATABASE',
    NULL,
    NULL,
    s.copy_options,
    NULL,
    'LH_ECOMMERCE_BRONZE',
    'benchmark',
    s.target_table,
    'FULL',
    NULL,
    0
FROM @Seed s
WHERE NOT EXISTS
(
    SELECT 1
    FROM control.ingestion_config c
    WHERE c.source_system = 'INGESTION_BENCHMARK'
      AND c.source_schema = 'benchmark'
      AND c.source_object = s.source_object
);

SELECT
    ingestion_config_id,
    source_system,
    source_schema,
    source_object,
    copy_options,
    target_schema,
    target_table,
    load_strategy,
    is_active
FROM control.ingestion_config
WHERE source_system = 'INGESTION_BENCHMARK'
ORDER BY source_object;
