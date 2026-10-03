/*
    06_set_benchmark_scenario.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Select exactly one benchmark scenario without recreating source data.

    Supported scenarios:
      DISABLE
      UNPARTITIONED_NONE
      UNPARTITIONED_DYNAMIC
      PARTITIONED_NONE
      PARTITIONED_PHYSICAL

    ParallelCopies:
      NULL = service-managed AUTO (recommended baseline)
      positive integer = explicit benchmark-backed override

    After running a non-DISABLE scenario, use the returned ingestion_config_id
    as p_config_id in pl_master_ingestion. Run DISABLE after the benchmark.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Scenario VARCHAR(40) = 'DISABLE';
DECLARE @ParallelCopies INT = NULL;

SET @Scenario = UPPER(@Scenario);

IF @Scenario NOT IN
(
    'DISABLE',
    'UNPARTITIONED_NONE',
    'UNPARTITIONED_DYNAMIC',
    'PARTITIONED_NONE',
    'PARTITIONED_PHYSICAL'
)
BEGIN
    THROW 51140, 'Unsupported benchmark scenario.', 1;
END;

IF @ParallelCopies IS NOT NULL AND @ParallelCopies <= 0
BEGIN
    THROW 51141, 'ParallelCopies must be NULL (AUTO) or a positive integer.', 1;
END;

/* Safety first: benchmark configs are disabled unless one scenario is selected. */
UPDATE control.ingestion_config
SET
    is_active = 0,
    updated_at = SYSUTCDATETIME()
WHERE source_system = 'INGESTION_BENCHMARK';

IF @Scenario <> 'DISABLE'
BEGIN
    DECLARE @SourceObject NVARCHAR(128);
    DECLARE @TargetTable NVARCHAR(128);
    DECLARE @CopyOptions NVARCHAR(MAX);

    IF @Scenario = 'UNPARTITIONED_NONE'
    BEGIN
        SET @SourceObject = 'copy_source_unpartitioned';
        SET @TargetTable = 'copy_benchmark_unpartitioned_none';
        SET @CopyOptions = N'{"partition_option":"NONE"}';
    END;

    IF @Scenario = 'UNPARTITIONED_DYNAMIC'
    BEGIN
        SET @SourceObject = 'copy_source_unpartitioned';
        SET @TargetTable = 'copy_benchmark_unpartitioned_dynamic';
        SET @CopyOptions =
            N'{"partition_option":"DYNAMIC_RANGE","partition_column":"benchmark_id"}';
    END;

    IF @Scenario = 'PARTITIONED_NONE'
    BEGIN
        SET @SourceObject = 'copy_source_partitioned';
        SET @TargetTable = 'copy_benchmark_partitioned_none';
        SET @CopyOptions = N'{"partition_option":"NONE"}';
    END;

    IF @Scenario = 'PARTITIONED_PHYSICAL'
    BEGIN
        SET @SourceObject = 'copy_source_partitioned';
        SET @TargetTable = 'copy_benchmark_partitioned_physical';
        SET @CopyOptions = N'{"partition_option":"PHYSICAL_PARTITIONS"}';
    END;

    IF @ParallelCopies IS NOT NULL
        SET @CopyOptions = JSON_MODIFY(@CopyOptions, '$.parallel_copies', @ParallelCopies);

    UPDATE control.ingestion_config
    SET
        copy_options = @CopyOptions,
        target_schema = 'benchmark',
        target_table = @TargetTable,
        is_active = 1,
        updated_at = SYSUTCDATETIME()
    WHERE source_system = 'INGESTION_BENCHMARK'
      AND source_schema = 'benchmark'
      AND source_object = @SourceObject;

    IF @@ROWCOUNT <> 1
        THROW 51142, 'Expected exactly one benchmark config; run 05_register_benchmark_configs.sql first.', 1;
END;

SELECT
    @Scenario AS selected_scenario,
    @ParallelCopies AS requested_parallel_copies,
    ingestion_config_id,
    source_object,
    copy_options,
    target_schema,
    target_table,
    is_active
FROM control.ingestion_config
WHERE source_system = 'INGESTION_BENCHMARK'
ORDER BY source_object;
