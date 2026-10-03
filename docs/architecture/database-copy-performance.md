# Database Copy Performance Strategy

## Status

Implemented for the current Azure SQL -> Bronze adapter.

The framework keeps orchestration in Fabric Data Factory Copy activities and uses
connector-native parallel partitioning rather than moving simple relational
extraction into Spark. Spark remains appropriate when the workload is a
distributed transformation rather than connector-native data movement.

Official references:

- https://learn.microsoft.com/en-us/fabric/data-factory/connector-sql-server-copy-activity
- https://learn.microsoft.com/en-us/azure/data-factory/connector-azure-sql-database
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

### Current Azure SQL contract

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

Current supported values:

```text
partition_option = NONE | DYNAMIC_RANGE
```

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

The current Azure SQL workers normalize metadata to:

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
WHERE ?DfDynamicRangePartitionCondition;
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
  AND <watermark_field> <= HIGH;
```

For `NONE`, only the normal watermark predicate is generated.

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

Azure SQL/SQL Server connectors also expose `PhysicalPartitionsOfTable`. That
connector capability is intentionally not advertised as implemented by this
project yet.

The current adapter adds technical columns through a custom source query, and the
project does not currently include a physically partitioned source-table fixture.
Physical-partition support should be added only with a real source definition and
acceptance test rather than claimed from connector capability alone.

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

## Static validation

Run:

```bash
python scripts/validation/validate_copy_tuning_contract.py
```

The validator checks that both Azure SQL workers keep separate AUTO and tuned
copy branches, that AUTO omits `parallelCopies`, that tuned mode binds the
metadata override, and that the dynamic-range placeholder/partition-column
contract is present.

This is static validation only. Fabric Git sync plus a non-empty pipeline run is
still required to acceptance-test the runtime expression shape and connector
behavior.

## Extension boundary

`copy_options` is a shared metadata envelope, but the keys an adapter supports
remain connector-aware.

A future Oracle/PostgreSQL/SQL Server adapter may reuse common keys when the
connector exposes equivalent behavior, but the DATABASE router must not assume
that every connector supports the same partition mechanisms.
