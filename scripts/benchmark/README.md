# Azure SQL Copy Performance Benchmark

## Purpose

This fixture is a dedicated scale/performance harness for the metadata-driven
ingestion framework. It is deliberately separate from `sql_ecommerce_db`.

The source data is generated once and kept permanently:

```text
sql_ingestion_benchmark
└─ benchmark
   ├─ copy_source_unpartitioned  10,000,000 rows
   └─ copy_source_partitioned    10,000,000 rows
```

Both tables have the same logical columns and deterministic values. The
partitioned table is physically partitioned by `event_date` into monthly 2026
partitions. Each row contains a fixed `CHAR(512)` payload so the benchmark moves
multiple gigabytes per full-table run rather than benchmarking only row-count
overhead.

## One-time setup

### Azure SQL: `sql_ingestion_benchmark`

Run:

```text
01_create_benchmark_source.sql
02_generate_benchmark_data.sql
03_grant_fabric_benchmark_read.sql
```

Before step 3, replace the password placeholder locally. Never commit the real
password.

The generator is resumable. It inserts the unpartitioned table in 100,000-row
batches and then copies the same ID ranges into the physically partitioned table.
At completion it validates 10M rows per table, compares a deterministic checksum,
and reports actual reserved/used storage.

### Fabric connection

Create an Azure SQL Database connection named:

```text
cn_azsql_ingestion_benchmark
```

Point it at `sql_ingestion_benchmark` using `fabric_benchmark_user`.

Then open `04_register_benchmark_connection.sql`, paste the Fabric connection ID
into the local variable, and run it against `sqldb_ingestion_control`.

### Control metadata

Run against `sqldb_ingestion_control`:

```text
05_register_benchmark_configs.sql
```

The two benchmark configs are registered with `is_active = 0`. This is
intentional: an ordinary all-config master run must never launch 10M-row
benchmark copies accidentally.

## Scenario selection

Edit only the two local variables in
`06_set_benchmark_scenario.sql`:

```sql
DECLARE @Scenario VARCHAR(40) = 'UNPARTITIONED_DYNAMIC';
DECLARE @ParallelCopies INT = NULL;
```

Supported scenarios:

```text
UNPARTITIONED_NONE
UNPARTITIONED_DYNAMIC
PARTITIONED_NONE
PARTITIONED_PHYSICAL
DISABLE
```

`@ParallelCopies = NULL` is the baseline and preserves Fabric service-managed
parallelism. Use a positive integer only for a later benchmark-backed tuning test.

The scenario script disables both benchmark configs, activates exactly one, sets
its `copy_options`, selects a scenario-specific Bronze target table, and returns
the `ingestion_config_id`.

Run `pl_master_ingestion` with:

```text
p_config_id = <returned ingestion_config_id>
p_run_type  = REGULAR
```

After the benchmark session, run the scenario script with:

```text
@Scenario = 'DISABLE'
```

Source benchmark data stays in Azure SQL permanently.

## Core comparison

Run at least:

| Scenario | Source physical layout | Copy partition strategy |
| --- | --- | --- |
| UNPARTITIONED_NONE | unpartitioned | NONE |
| UNPARTITIONED_DYNAMIC | unpartitioned | DYNAMIC_RANGE on benchmark_id |
| PARTITIONED_NONE | monthly physical partitions | NONE |
| PARTITIONED_PHYSICAL | monthly physical partitions | PHYSICAL_PARTITIONS |

Record the Copy Activity output/monitoring metrics for each run, especially
duration, rows, data volume, throughput, and used parallel copies. Also observe
Azure SQL resource pressure during the run.

Do not define success as "parallel must be X% faster." A useful benchmark explains
where the bottleneck moves. If source compute or I/O saturates, increased
parallelism may provide little benefit; that is a valid result.

## Storage safety

The fixture is designed for a 32-GB Azure SQL free database by keeping only two
10M-row source tables, each with one clustered index and a 512-byte payload.

After generation, use the storage result set from
`02_generate_benchmark_data.sql` as the source of truth. If actual allocated
storage is unexpectedly high, stop before adding any additional benchmark data.
Do not scale the fixture beyond 10M rows per table until actual storage headroom
has been reviewed.
