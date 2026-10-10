/*
    02_generate_data.sql
    Target: SQL Server 2022 Developer on EC2 database (sql_ingestion_benchmark)
    Purpose: Generate a permanent 10M-row source in each benchmark table.

    Design:
      - 10,000,000 rows per table.
      - Approximately 512 bytes of explicit payload per row plus fixed columns.
      - Both tables contain the same deterministic logical rows.
      - Inserts are committed in batches to avoid one massive transaction.
      - The script is resumable when IDs are contiguous from 1..MAX(benchmark_id).

    Storage intent:
      - Keep both tables permanently so benchmark scenarios do not require
        drop/recreate cycles.
      - Measure actual reserved/used size after generation rather than relying
        only on a theoretical row-width estimate.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

/* Developer Edition benchmark: 10M rows in EACH table from the start.
   Run in resumable 100k-row batches. Verify EC2 disk/log free space first. */
DECLARE @TargetRows BIGINT = 10000000;
DECLARE @BatchSize  INT = 100000;
DECLARE @BaseDate   DATE = '2026-01-01';

IF OBJECT_ID('benchmark.copy_source_unpartitioned', 'U') IS NULL
   OR OBJECT_ID('benchmark.copy_source_partitioned', 'U') IS NULL
BEGIN
    THROW 51110, 'Run scripts/source/benchmark-db/01_create_schema.sql first.', 1;
END;

/* ---------- Phase 1: deterministic unpartitioned source ---------- */
DECLARE @ExistingRows BIGINT;
DECLARE @MaxId BIGINT;

SELECT
    @ExistingRows = COUNT_BIG(*),
    @MaxId = COALESCE(MAX(benchmark_id), 0)
FROM benchmark.copy_source_unpartitioned;

IF @ExistingRows <> @MaxId
BEGIN
    THROW 51111, 'Unpartitioned benchmark IDs are not contiguous from 1..MAX; review before resuming.', 1;
END;

IF @ExistingRows > @TargetRows
BEGIN
    THROW 51112, 'Unpartitioned benchmark table already exceeds TargetRows.', 1;
END;

DECLARE @StartId BIGINT = @MaxId + 1;

WHILE @StartId <= @TargetRows
BEGIN
    DECLARE @ThisBatch INT =
        CASE
            WHEN @TargetRows - @StartId + 1 > @BatchSize THEN @BatchSize
            ELSE CONVERT(INT, @TargetRows - @StartId + 1)
        END;

    ;WITH N AS
    (
        SELECT TOP (@ThisBatch)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
        FROM sys.all_objects a
        CROSS JOIN sys.all_objects b
    ),
    R AS
    (
        SELECT
            benchmark_id = @StartId + rn - 1
        FROM N
    )
    INSERT INTO benchmark.copy_source_unpartitioned
    (
        benchmark_id,
        event_date,
        event_timestamp,
        customer_id,
        region_code,
        status_code,
        amount,
        metric_1,
        metric_2,
        payload
    )
    SELECT
        r.benchmark_id,
        DATEADD(DAY, CONVERT(INT, (r.benchmark_id - 1) % 365), @BaseDate),
        DATEADD(
            MILLISECOND,
            CONVERT(INT, r.benchmark_id % 1000),
            DATEADD(
                SECOND,
                CONVERT(INT, r.benchmark_id % 86400),
                CONVERT(DATETIME2(3), DATEADD(DAY, CONVERT(INT, (r.benchmark_id - 1) % 365), @BaseDate))
            )
        ),
        1 + (r.benchmark_id % 1000000),
        CASE r.benchmark_id % 8
            WHEN 0 THEN 'TH'
            WHEN 1 THEN 'SG'
            WHEN 2 THEN 'MY'
            WHEN 3 THEN 'VN'
            WHEN 4 THEN 'ID'
            WHEN 5 THEN 'PH'
            WHEN 6 THEN 'JP'
            ELSE 'AU'
        END,
        CASE r.benchmark_id % 5
            WHEN 0 THEN 'NEW'
            WHEN 1 THEN 'ACTIVE'
            WHEN 2 THEN 'PENDING'
            WHEN 3 THEN 'CLOSED'
            ELSE 'REVIEW'
        END,
        CONVERT(DECIMAL(18,2), (r.benchmark_id % 10000000) / 100.0),
        CONVERT(INT, r.benchmark_id % 100000),
        r.benchmark_id * 17,
        CONVERT(
            CHAR(512),
            LEFT(
                CONCAT(
                    'BENCH-',
                    RIGHT(CONCAT(REPLICATE('0', 20), CONVERT(VARCHAR(20), r.benchmark_id)), 20),
                    '-',
                    REPLICATE('X', 512)
                ),
                512
            )
        )
    FROM R r;

    SET @StartId += @ThisBatch;

    IF ((@StartId - 1) % 1000000) = 0 OR @StartId > @TargetRows
        PRINT CONCAT('Unpartitioned rows generated: ', FORMAT(@StartId - 1, 'N0'));
END;

/* ---------- Phase 2: same logical rows, physically partitioned ---------- */
SELECT
    @ExistingRows = COUNT_BIG(*),
    @MaxId = COALESCE(MAX(benchmark_id), 0)
FROM benchmark.copy_source_partitioned;

IF @ExistingRows <> @MaxId
BEGIN
    THROW 51113, 'Partitioned benchmark IDs are not contiguous from 1..MAX; review before resuming.', 1;
END;

IF @ExistingRows > @TargetRows
BEGIN
    THROW 51114, 'Partitioned benchmark table already exceeds TargetRows.', 1;
END;

SET @StartId = @MaxId + 1;

WHILE @StartId <= @TargetRows
BEGIN
    SET @ThisBatch =
        CASE
            WHEN @TargetRows - @StartId + 1 > @BatchSize THEN @BatchSize
            ELSE CONVERT(INT, @TargetRows - @StartId + 1)
        END;

    INSERT INTO benchmark.copy_source_partitioned
    (
        benchmark_id,
        event_date,
        event_timestamp,
        customer_id,
        region_code,
        status_code,
        amount,
        metric_1,
        metric_2,
        payload
    )
    SELECT
        benchmark_id,
        event_date,
        event_timestamp,
        customer_id,
        region_code,
        status_code,
        amount,
        metric_1,
        metric_2,
        payload
    FROM benchmark.copy_source_unpartitioned
    WHERE benchmark_id >= @StartId
      AND benchmark_id < @StartId + @ThisBatch;

    SET @StartId += @ThisBatch;

    IF ((@StartId - 1) % 1000000) = 0 OR @StartId > @TargetRows
        PRINT CONCAT('Partitioned rows generated: ', FORMAT(@StartId - 1, 'N0'));
END;

/* ---------- Acceptance checks ---------- */
IF (SELECT COUNT_BIG(*) FROM benchmark.copy_source_unpartitioned) <> @TargetRows
    THROW 51115, 'Unpartitioned benchmark row-count validation failed.', 1;

IF (SELECT COUNT_BIG(*) FROM benchmark.copy_source_partitioned) <> @TargetRows
    THROW 51116, 'Partitioned benchmark row-count validation failed.', 1;

IF
(
    SELECT CHECKSUM_AGG(BINARY_CHECKSUM(
        benchmark_id,
        event_date,
        event_timestamp,
        customer_id,
        region_code,
        status_code,
        amount,
        metric_1,
        metric_2,
        payload
    ))
    FROM benchmark.copy_source_unpartitioned
)
<>
(
    SELECT CHECKSUM_AGG(BINARY_CHECKSUM(
        benchmark_id,
        event_date,
        event_timestamp,
        customer_id,
        region_code,
        status_code,
        amount,
        metric_1,
        metric_2,
        payload
    ))
    FROM benchmark.copy_source_partitioned
)
BEGIN
    THROW 51117, 'Benchmark table content checksum validation failed.', 1;
END;

/* Per-table actual storage. */
SELECT
    s.name AS schema_name,
    t.name AS table_name,
    SUM(ps.row_count) AS row_count,
    CAST(SUM(ps.reserved_page_count) * 8.0 / 1024 AS DECIMAL(18,2)) AS reserved_mb,
    CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS DECIMAL(18,2)) AS used_mb
FROM sys.dm_db_partition_stats ps
JOIN sys.tables t
    ON t.object_id = ps.object_id
JOIN sys.schemas s
    ON s.schema_id = t.schema_id
WHERE s.name = 'benchmark'
  AND t.name IN ('copy_source_unpartitioned', 'copy_source_partitioned')
GROUP BY s.name, t.name
ORDER BY t.name;

/* Populated physical partitions. */
SELECT
    p.partition_number,
    MIN(b.event_date) AS min_event_date,
    MAX(b.event_date) AS max_event_date,
    COUNT_BIG(*) AS row_count
FROM benchmark.copy_source_partitioned b
JOIN sys.partitions p
    ON p.object_id = OBJECT_ID('benchmark.copy_source_partitioned')
   AND p.index_id = 1
   AND p.partition_number = $PARTITION.pf_benchmark_event_date(b.event_date)
GROUP BY p.partition_number
ORDER BY p.partition_number;

/* Allocated database-file size; check EC2 EBS free space and SQL log growth separately. */
SELECT
    name AS logical_file_name,
    type_desc,
    CAST(size * 8.0 / 1024 AS DECIMAL(18,2)) AS allocated_mb,
    CASE
        WHEN max_size = -1 THEN NULL
        ELSE CAST(max_size * 8.0 / 1024 AS DECIMAL(18,2))
    END AS configured_max_mb
FROM sys.database_files
ORDER BY file_id;
