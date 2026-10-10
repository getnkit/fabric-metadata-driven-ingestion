/*
    01_create_schema.sql
    Target: SQL Server 2022 Developer on EC2 database (sql_benchmark_db)
    Purpose: Create two permanent, logically equivalent benchmark source tables:
             one unpartitioned and one physically partitioned.

    The benchmark is intentionally isolated from the e-commerce fixture so scale
    testing does not distort the business-demo model.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF SCHEMA_ID('benchmark') IS NULL
    EXEC('CREATE SCHEMA benchmark');
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.partition_functions
    WHERE name = 'pf_benchmark_event_date'
)
BEGIN
    EXEC(
        'CREATE PARTITION FUNCTION pf_benchmark_event_date (DATE)
         AS RANGE RIGHT FOR VALUES
         (
             ''2026-02-01'',
             ''2026-03-01'',
             ''2026-04-01'',
             ''2026-05-01'',
             ''2026-06-01'',
             ''2026-07-01'',
             ''2026-08-01'',
             ''2026-09-01'',
             ''2026-10-01'',
             ''2026-11-01'',
             ''2026-12-01''
         );'
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.partition_schemes
    WHERE name = 'ps_benchmark_event_date'
)
BEGIN
    EXEC(
        'CREATE PARTITION SCHEME ps_benchmark_event_date
         AS PARTITION pf_benchmark_event_date
         ALL TO ([PRIMARY]);'
    );
END;
GO

IF OBJECT_ID('benchmark.copy_source_unpartitioned', 'U') IS NULL
BEGIN
    CREATE TABLE benchmark.copy_source_unpartitioned
    (
        benchmark_id     BIGINT NOT NULL,
        event_date       DATE NOT NULL,
        event_timestamp  DATETIME2(3) NOT NULL,
        customer_id      BIGINT NOT NULL,
        region_code      CHAR(2) NOT NULL,
        status_code      VARCHAR(12) NOT NULL,
        amount            DECIMAL(18,2) NOT NULL,
        metric_1          INT NOT NULL,
        metric_2          BIGINT NOT NULL,
        payload           CHAR(512) NOT NULL
    );

    CREATE CLUSTERED INDEX CX_copy_source_unpartitioned
        ON benchmark.copy_source_unpartitioned(benchmark_id, event_date);
END;
GO

IF OBJECT_ID('benchmark.copy_source_partitioned', 'U') IS NULL
BEGIN
    CREATE TABLE benchmark.copy_source_partitioned
    (
        benchmark_id     BIGINT NOT NULL,
        event_date       DATE NOT NULL,
        event_timestamp  DATETIME2(3) NOT NULL,
        customer_id      BIGINT NOT NULL,
        region_code      CHAR(2) NOT NULL,
        status_code      VARCHAR(12) NOT NULL,
        amount            DECIMAL(18,2) NOT NULL,
        metric_1          INT NOT NULL,
        metric_2          BIGINT NOT NULL,
        payload           CHAR(512) NOT NULL
    );

    CREATE CLUSTERED INDEX CX_copy_source_partitioned
        ON benchmark.copy_source_partitioned(benchmark_id, event_date)
        ON ps_benchmark_event_date(event_date);
END;
GO

/* Verify that the two tables have the same logical columns. */
IF EXISTS
(
    SELECT
        c.name,
        TYPE_NAME(c.user_type_id) AS type_name,
        c.max_length,
        c.precision,
        c.scale,
        c.is_nullable
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('benchmark.copy_source_unpartitioned')

    EXCEPT

    SELECT
        c.name,
        TYPE_NAME(c.user_type_id) AS type_name,
        c.max_length,
        c.precision,
        c.scale,
        c.is_nullable
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('benchmark.copy_source_partitioned')
)
OR EXISTS
(
    SELECT
        c.name,
        TYPE_NAME(c.user_type_id) AS type_name,
        c.max_length,
        c.precision,
        c.scale,
        c.is_nullable
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('benchmark.copy_source_partitioned')

    EXCEPT

    SELECT
        c.name,
        TYPE_NAME(c.user_type_id) AS type_name,
        c.max_length,
        c.precision,
        c.scale,
        c.is_nullable
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('benchmark.copy_source_unpartitioned')
)
BEGIN
    THROW 51100, 'Benchmark tables do not have the same logical schema.', 1;
END;
GO

/* Physical-partition evidence used later by the benchmark. */
SELECT
    s.name AS schema_name,
    t.name AS table_name,
    pf.name AS partition_function_name,
    c.name AS partition_column,
    CASE WHEN pf.name IS NULL THEN 'NO' ELSE 'YES' END AS has_physical_partition
FROM sys.tables t
JOIN sys.schemas s
    ON s.schema_id = t.schema_id
LEFT JOIN sys.indexes i
    ON i.object_id = t.object_id
   AND i.index_id IN (0, 1)
LEFT JOIN sys.index_columns ic
    ON ic.object_id = i.object_id
   AND ic.index_id = i.index_id
   AND ic.partition_ordinal > 0
LEFT JOIN sys.columns c
    ON c.object_id = ic.object_id
   AND c.column_id = ic.column_id
LEFT JOIN sys.partition_schemes ps
    ON ps.data_space_id = i.data_space_id
LEFT JOIN sys.partition_functions pf
    ON pf.function_id = ps.function_id
WHERE s.name = 'benchmark'
  AND t.name IN ('copy_source_unpartitioned', 'copy_source_partitioned')
ORDER BY t.name;
GO
