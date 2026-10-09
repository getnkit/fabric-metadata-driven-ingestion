# Amazon RDS for SQL Server Copy Performance Benchmark

## Purpose

This fixture is a dedicated scale/performance harness for the metadata-driven
ingestion framework. It is deliberately separate from `sql_ecommerce_db`.

The source data is generated once and kept permanently:

```text
sql_ingestion_benchmark
└─ benchmark
   ├─ copy_source_unpartitioned   1,000,000 rows
   └─ copy_source_partitioned     1,000,000 rows
```

Both tables have the same logical columns and deterministic values. The
partitioned table is physically partitioned by `event_date` into monthly 2026
partitions. Each row contains a fixed `CHAR(512)` payload so the benchmark moves
multiple gigabytes per full-table run rather than benchmarking only row-count
overhead.

## One-time setup

### Amazon RDS for SQL Server: `sql_ingestion_benchmark`

Run:

```text
01_create_benchmark_source.sql
02_generate_benchmark_data.sql
03_grant_fabric_benchmark_read.sql
```

Before step 3, replace the password placeholder locally. Never commit the real
password.

Create database `sql_ingestion_benchmark` on the **existing RDS instance** as administrator first; select that database before running source/fixture scripts. Script 03 creates a SQL Server login in master and user mapped to the benchmark database. The generator is resumable. It inserts the unpartitioned table in 100,000-row
batches and then copies the same ID ranges into the physically partitioned table.
At completion it validates 1M rows per table, compares a deterministic checksum,
and reports actual reserved/used storage.

### Fabric connection

Create a **Fabric Amazon RDS for SQL Server** connection named:

```text
cn_rds_sql_server_ingestion_benchmark
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
intentional: an ordinary all-config master run must never launch 1M-row
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

Source benchmark data stays in Amazon RDS for SQL Server permanently.

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
Amazon RDS for SQL Server resource pressure during the run.

Do not define success as "parallel must be X% faster." A useful benchmark explains
where the bottleneck moves. If source compute or I/O saturates, increased
parallelism may provide little benefit; that is a valid result.

## Storage safety

The benchmark uses the existing RDS SQL Server **instance**, with a separate database `sql_ingestion_benchmark`. The default fixture is deliberately reduced to **1M rows per table** to leave storage margin within SQL Server Express's **10 GB per database** limit. The original Azure SQL 10M x two tables profile is NOT portable unchanged to Express.

After generation, use the storage result set from
`02_generate_benchmark_data.sql` as the source of truth. If actual allocated
storage is unexpectedly high, stop before adding any additional benchmark data.
Do not scale the fixture beyond 1M rows per table until actual storage headroom
has been reviewed.

## Cost and reproducibility guardrails

RDS **SQL Server Express** has a 10 GB maximum *per database*. Keep the e-commerce and benchmark fixtures in **separate databases on one RDS instance**, and monitor allocated DB size and AWS charges. Default `02_generate_benchmark_data.sql` now generates 1,000,000 rows **in each** table (two copies). A later 10M-row benchmark requires a capacity/edition/storage and budget review; don't simply change `@TargetRows` on Express. Capture instance class, edition, IOPS, CPU load, network egress, row counts and parallelism for each run. Benchmark results are **not directly comparable** with the earlier Azure SQL compute configuration.

`PARTITIONED_PHYSICAL` also requires a source table that is genuinely partitioned; validate DDL support, actual partition layout and copy behavior on the chosen SQL Server version/edition before reporting a result. Do not assume higher parallelism is faster on a burstable RDS instance.
