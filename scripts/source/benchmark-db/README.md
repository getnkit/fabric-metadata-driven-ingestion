# SQL Server 2022 Developer on EC2 Copy Performance Benchmark

## Purpose

This fixture is a dedicated scale/performance harness for the metadata-driven
ingestion framework. It is deliberately separate from `sql_ecommerce_db`.

The source data is generated once and kept permanently:

```text
sql_benchmark_db
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

### SQL Server 2022 Developer on EC2: `sql_benchmark_db`

Run:

```text
01_create_schema.sql
02_generate_data.sql
03_grant_reader.sql
```

Before step 3, replace the password placeholder locally. Never commit the real
password.

Create `sql_benchmark_db` on the existing EC2 SQL Server instance first, then select it before running the source scripts.

When executing SQL files through DBeaver, use **Execute SQL Script**
(`Option+X` on macOS) with SQL Server's `GO` batch delimiter enabled.

Script 03 creates a SQL Server login in master and user mapped to the benchmark database. The generator is resumable. It inserts the unpartitioned table in 100,000-row
batches and then copies the same ID ranges into the physically partitioned table.
At completion it validates 10M rows per table, compares a deterministic checksum,
and reports actual reserved/used storage.

### Fabric connection

Create a **Fabric SQL Server 2022 Developer on EC2** connection named:

```text
cn_src_sql_server_benchmark_db
```

Point it at `sql_benchmark_db` using `fabric_benchmark_reader`.
The Control Plane logical connection reference is `SQL_SERVER_BENCHMARK`
and benchmark `source_system` is `BENCHMARK`.

Benchmark registration is integrated into the core Control Plane seeds;
there is **no separate benchmark-registration script**:

1. **Fresh DEV:** set optional `@BenchmarkSourceConnectionId` alongside
   the five core IDs in `scripts/control/03_seed_connection_settings.sql`;
   run `03` followed by `scripts/control/04_seed_ingestion_metadata.sql`.
2. **Existing seeded DEV:** set **only** `@BenchmarkSourceConnectionId` in
   seed `03` (leave all five core bindings `NULL`) and run it.
   Then set `@BenchmarkOnly = 1` in seed `04` and run it to insert just the
   two missing benchmark configs without updating existing demo settings.

The two benchmark configs are `is_active = 0` when created. The core metadata
seed never overwrites existing benchmark configs, so an active benchmark
scenario is not changed by a later seed run. The scenario selector below
controls activation; an all-config master run should not include benchmarks
until one is explicitly enabled.

## Scenario selection

Edit only the two local variables in
`scripts/control/05_set_benchmark_scenario.sql`:

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

The scenario script atomically disables other benchmark configs, activates exactly one, sets
its `copy_options`, selects a scenario-specific Bronze target table, and returns
the `ingestion_config_id`.

Run `pl_ingest_orchestrator` with an explicit request:

```text
p_run_requests = [
  {
    "config_id": <returned ingestion_config_id>,
    "run_type": "REGULAR",
    "lower_bound": "",
    "upper_bound": ""
  }
]
```

The benchmark config remains metadata-driven; `load_strategy` and copy options
come from `control.ingestion_config`.

After the benchmark session, run the scenario script with:

```text
@Scenario = 'DISABLE'
```

Source benchmark data stays in the EC2 SQL Server Developer test database between runs.

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
SQL Server 2022 Developer on EC2 resource pressure during the run.

Do not define success as "parallel must be X% faster." A useful benchmark explains
where the bottleneck moves. If source compute or I/O saturates, increased
parallelism may provide little benefit; that is a valid result.

## Storage safety

The benchmark uses a **separate database on the existing EC2 SQL Server 2022 Developer container**. Default is **10,000,000 rows in each of two tables** with `CHAR(512)` payload. Data is generated in resumable 100,000-row batches and is retained for repeatable Copy performance tests. Confirm sufficient free space before starting (an 80 GiB gp3 root EBS volume is only an initial sizing assumption, not a guarantee). Review allocated MDF/LDF size, free disk space, tempdb, indexing overhead and memory pressure while generating data. The e-commerce source data volume is unchanged.

## Cost and reproducibility guardrails

SQL Server **Developer Edition is for development/testing, not production use**. Capture EC2 instance type, EBS size/IOPS, SQL Server edition, CPU and memory load, network egress, row counts and effective parallelism for each run. Benchmark results are **not directly comparable** with the earlier Azure SQL compute configuration.

`PARTITIONED_PHYSICAL` also requires a source table that is genuinely partitioned; validate DDL support, actual partition layout and copy behavior on the chosen SQL Server version/edition before reporting a result. Do not assume higher parallelism is faster on a burstable EC2 SQL Server instance.
