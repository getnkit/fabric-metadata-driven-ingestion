# Database Copy Performance Strategy

## Status

Implemented for the current Amazon RDS for SQL Server -> Bronze adapter.

The framework keeps orchestration in Fabric Data Factory Copy activities and uses
connector-native parallel partitioning rather than moving simple relational
extraction into Spark. Spark remains appropriate when the workload is a
distributed transformation rather than connector-native data movement.

Official references:

- https://learn.microsoft.com/en-us/fabric/data-factory/connector-sql-server-copy-activity
- https://learn.microsoft.com/en-us/fabric/data-factory/connector-amazon-rds-for-sql-server-copy-activity
- https://learn.microsoft.com/en-us/azure/data-factory/copy-activity-performance-features

## Metadata model

`control.ingestion_config.copy_options` is optional JSON execution metadata.

It is intentionally separate from `source_options`:

```text
source_options
= how source data/file content is read or parsed

copy_options
= how connector-native data movement is executed/tuned
```

Keeping copy execution hints in one JSON column avoids adding many nullable,
connector-specific columns to the shared ingestion configuration table.

### Current Amazon RDS for SQL Server contract

Default:

```sql
copy_options = NULL
```

means:

```text
partition_option = NONE
parallel_copies  = service-managed AUTO
```

Dynamic range example:

```json
{
  "partition_option": "DYNAMIC_RANGE",
  "partition_column": "order_item_id"
}
```

Optional benchmark-backed override:

```json
{
  "partition_option": "DYNAMIC_RANGE",
  "partition_column": "order_item_id",
  "parallel_copies": 8
}
```

Current Amazon RDS for SQL Server support:

```text
FULL:
  partition_option = NONE | DYNAMIC_RANGE | PHYSICAL_PARTITIONS

INCREMENTAL:
  partition_option = NONE | DYNAMIC_RANGE
```

`PHYSICAL_PARTITIONS` is currently a FULL-load capability in this project. It
uses a native table source so Fabric can discover the physical partition
definition directly.

`DYNAMIC_RANGE` requires an explicit `partition_column`. The current adapter
does not silently auto-select a PK/index because an explicit column makes the
per-object execution policy reviewable and deterministic.

`parallel_copies` is optional. Do not populate it from row count alone. Omitted
means Fabric chooses the parallel-copy degree. A positive integer is an explicit
operator override and should be retained only after representative performance
testing shows a measurable benefit or a source-load constraint requires it.

Internally the pipeline normalizes an omitted `parallel_copies` to parameter
value `0` only as a routing sentinel. The value `0` is never passed to the
Copy activity. The AUTO branch omits the `parallelCopies` property completely.

## Runtime flow

The current Amazon RDS for SQL Server workers normalize metadata to:

```text
p_copy_partition_option
p_copy_partition_column
p_copy_parallel_copies
```

and validate the supported combination before data movement.

Execution then selects one of two copy modes:

```text
p_copy_parallel_copies = 0
  -> copy_source_to_bronze_auto
     (parallelCopies omitted)

p_copy_parallel_copies > 0
  -> copy_source_to_bronze_tuned
     (parallelCopies = configured override)
```

Both modes use the same partition strategy.

For `NONE`:

```text
partitionOption = None
```

For `DYNAMIC_RANGE`:

```text
partitionOption = DynamicRange
partitionColumnName = configured partition_column
```

The query contains Fabric's required range placeholder:

```sql
?DfDynamicRangePartitionCondition
```

### FULL query shape

```sql
SELECT
    *,
    <technical metadata columns>
FROM <schema>.<table>
WHERE ?DfDynamicRangePartitionCondition
```

The WHERE clause is added only for `DYNAMIC_RANGE`.

### INCREMENTAL query shape

```sql
SELECT
    *,
    <technical metadata columns>
FROM <schema>.<table>
WHERE ?DfDynamicRangePartitionCondition
  AND <watermark_field> > LOW
  AND <watermark_field> <= HIGH
```

For `NONE`, only the normal watermark predicate is generated.

The custom-query templates deliberately omit a terminal semicolon. For
`DYNAMIC_RANGE`, Fabric can wrap the source query as a derived table while
discovering partition bounds. A terminal `;` inside that wrapper can make the
wrapped SQL invalid even though the same standalone query is valid SQL.

Dynamic-range bounds are intentionally not stored as permanent metadata in the
current framework. Fabric can derive the range for the configured partition
column. Static bounds age as source data grows and should only be introduced if a
real benchmark proves that range discovery is material.

## Seeded example

The current seed enables dynamic range on the largest relational demo object:

```text
sales.order_items
partition_option = DYNAMIC_RANGE
partition_column = order_item_id
parallel_copies  = AUTO
```

The default fixture has only 60,000 rows, so this proves routing/functionality,
not a large-scale performance gain. Production tuning claims require a larger
representative dataset and measured run metrics.

Other DATABASE seed objects remain `copy_options = NULL`, providing a baseline
for the normal non-partitioned path.

## Physical partitions

Amazon RDS for SQL Server FULL ingestion now supports:

```json
{
  "partition_option": "PHYSICAL_PARTITIONS"
}
```

The physical-partition branch deliberately does not use `sqlReaderQuery`.
Instead it points the Amazon RDS for SQL Server dataset at the configured source schema/table and
sets:

```text
partitionOption = PhysicalPartitionsOfTable
```

Fabric therefore discovers the source table's physical partition definition
rather than receiving a custom-query range predicate.

The framework still preserves its three relational Bronze technical columns by
using Copy Activity `additionalColumns`:

```text
_batch_id
_pipeline_run_id
_ingestion_timestamp
```

AUTO and explicit `parallel_copies` modes are both supported. As with Dynamic
Range, omitted `parallel_copies` means service-managed parallelism.

Physical partitions are intentionally not enabled for the current INCREMENTAL
adapter. The benchmark and the initial implementation use the connector's
documented full-load physical-partition scenario; incremental semantics continue
to use the existing LOW/HIGH custom query with NONE or DYNAMIC_RANGE.

The prior Azure SQL Copy UI was observed on 2026-10-06, but that evidence
must not be treated as an RDS runtime test. Microsoft's RDS connector
documentation describes Query + Dynamic Range as well as physical-table
partition modes. This framework uses Query only with NONE/DYNAMIC_RANGE,
and uses the physical-partition source TABLE mode only for FULL loads.
Confirm the RDS UI/JSON behavior after connecting to an actual RDS instance. Incremental ingestion requires a custom watermark query, for example:

```sql
WHERE <watermark_field> > LOW
  AND <watermark_field> <= HIGH
```

Dynamic range has the documented `?DfDynamicRangePartitionCondition`
placeholder that can be embedded in that custom query. The current connector
surface does not expose an equivalent custom-query pattern for physical table
partitions. Therefore the framework contract is:

```text
FULL:
  NONE | DYNAMIC_RANGE | PHYSICAL_PARTITIONS

INCREMENTAL:
  NONE | DYNAMIC_RANGE
```

This is a framework capability decision based on the documented/custom-query
surface and observed Fabric UI behavior; it should not be interpreted as a
general claim that Amazon RDS for SQL Server can never combine incremental extraction with a
physically partitioned source table.

### Permanent benchmark fixture

The benchmark creates a separate **database on the same Amazon RDS for SQL Server instance**:

```text
sql_ingestion_benchmark
```

with two permanent tables containing the same deterministic logical rows:

```text
benchmark.copy_source_unpartitioned
benchmark.copy_source_partitioned
```

Default scale:

```text
1,000,000 rows per table
CHAR(512) payload per row
same logical schema and generated values
```

The partitioned table uses monthly `event_date` partitions for 2026. Both tables
remain in the source database after setup; benchmark scenarios change only
metadata/runtime strategy, not the source data.

The benchmark scenarios are:

```text
UNPARTITIONED_NONE
UNPARTITIONED_DYNAMIC
PARTITIONED_NONE
PARTITIONED_PHYSICAL
```

This separates physical-layout effects from Copy Activity execution strategy and
avoids inflating the e-commerce business fixture only to manufacture a scale
test.

## Benchmark procedure

Use representative data volume and compare the same source/sink path.

Recommended sequence:

```text
1. AUTO parallelism + NONE or DYNAMIC_RANGE baseline
2. Record rows, bytes, duration, throughput, and source DB load
3. If needed, test a small explicit parallel_copies override
4. Increase gradually only while throughput materially improves
5. Stop when source/sink pressure rises without meaningful throughput gain
6. Persist the override in copy_options only when evidence supports it
```

Do not infer the number from row count alone. Row width, source indexes, skew,
database compute, network capacity, sink throughput, concurrent workloads, and
the selected partition column all affect the useful parallelism.

## Extension boundary

`copy_options` is a shared metadata envelope, but the keys an adapter supports
remain connector-aware.

A future Oracle/PostgreSQL/SQL Server adapter may reuse common keys when the
connector exposes equivalent behavior, but the DATABASE router must not assume
that every connector supports the same partition mechanisms.

### RDS Express sizing note

The RDS migration keeps the same NONE/DYNAMIC_RANGE/PHYSICAL_PARTITIONS
Copy strategy contract and SQL Server timestamp watermark expressions. The
starter Benchmark Generator targets **1,000,000 rows per table** (not the former
Azure SQL 10M rows/table) to fit SQL Server Express's per-database limit with
headroom. More rows or another Edition require explicit budget/storage
review. Check the Fabric RDS connector source settings at runtime; identical
SQL syntax does not guarantee identical Connector JSON behavior.
