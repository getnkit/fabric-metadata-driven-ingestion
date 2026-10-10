# Database Ingestion Extensibility

## Status

Accepted for the current blueprint.

## Current architecture

```text
pl_ingest_orchestrator
  -> pl_ingest_object_controller
      -> DATABASE
          -> pl_ingest_database_router
              -> source_connection_type|load_strategy
                  -> SQL_SERVER|FULL
                      -> pl_ingest_sql_server_full_adapter
                  -> SQL_SERVER|INCREMENTAL
                      -> pl_ingest_sql_server_incremental_adapter
```

The DATABASE router is intentionally a thin pattern-level connector/strategy
router. Its purpose is to keep physical database technology and connector-specific
load implementation out of the object controller while avoiding a separate router
pipeline for every FULL/INCREMENTAL combination.

Batch ingestion has one target-type invariant: Bronze is a Fabric Lakehouse.
The object controller validates `target_connection_type = LAKEHOUSE` before
routing, so target type is not duplicated in the route key. Target identity
(`target_conn_ref`, connection settings, schema, and table) remains metadata
because it selects the actual Lakehouse/table instance.

## Framework-owned behavior

The framework owns semantics that must stay consistent across database vendors:

- REGULAR / BACKFILL behavior
- processing boundary semantics
- current watermark state
- no-new-data behavior
- Bronze append-only guarantees
- audit/finalization behavior
- optimistic watermark protection

A vendor adapter must not redefine these semantics.

## Connector-owned behavior

A database connector implementation may own behavior that genuinely depends on
the source technology, including:

- connector configuration
- source-specific query syntax
- identifier quoting
- source boundary capture
- extraction predicate syntax
- source type mapping
- connector-specific partition/pushdown options
- connector-specific Copy parallelism overrides when benchmark evidence justifies them

## Data consistency policy

Data transfer consistency is a framework requirement, but the physical validation
mechanism remains connector-aware.

When the actual source-to-sink Copy pair and execution mode support Fabric's
native Data Consistency Verification, the connector adapter should enable it and
treat Copy success/failure as the consistency gate. The pipeline should not add a
second row-count comparison for the same transfer.

When native verification is unsupported or inapplicable, the adapter must use a
pattern-appropriate framework fallback instead of silently skipping consistency
validation.

The current SQL Server 2022 Developer on EC2 FULL and INCREMENTAL Copy paths enable native Data
Consistency Verification. Future database adapters must confirm support for their
actual Copy pair and execution mode rather than inheriting this setting blindly.

## Copy type-conversion policy

All six SQL Server 2022 Developer on EC2 -> Lakehouse Bronze Copy branches (FULL Query/Table AUTO/TUNED
and INCREMENTAL Query AUTO/TUNED) use automatic source-schema mapping with
`TabularTranslator.typeConversion = true` and
`typeConversionSettings.allowDataTruncation = false`.

This is a fail-fast ingestion policy: do not allow the Copy type-conversion
layer to silently truncate source values when converting to destination types.
The setting does **not** guarantee byte-for-byte equivalence or prevent every
lossy native SQL -> Fabric interim type -> Delta mapping. A type that cannot
be represented in the sink may fail rather than being silently accepted; validate
real source type compatibility when onboarding new tables. Bronze remains
append-only and metadata-driven, without per-table hardcoded column mapping.

SFTP Binary source-to-Landing transfer and the Spark delimited-text parser
do not use this TabularTranslator setting; they preserve their existing
connector/reader-specific behavior.

## Copy performance metadata

Connector-native performance hints are stored in the optional
`control.ingestion_config.copy_options` JSON envelope. The current SQL Server 2022 Developer on EC2
adapter supports `NONE` and `DYNAMIC_RANGE` partition strategies plus an
optional benchmark-backed `parallel_copies` override.

See [Database Copy Performance Strategy](database-copy-performance.md).

The router passes normalized execution metadata to the connector adapter; it does
not interpret connector-specific partition semantics itself.

## Extension rule

When a second database connector such as Oracle or PostgreSQL is
implemented, add it behind the DATABASE connector router first.

Do not permanently clone framework semantics across vendor pipelines. Compare the
two real implementations and extract common database orchestration only where the
shared contract is proven.

The likely future shape is:

```text
pl_ingest_database_router
  -> source_connection_type|load_strategy
       -> SQL_SERVER|FULL        -> SQL Server 2022 Developer on EC2 FULL adapter
       -> SQL_SERVER|INCREMENTAL -> SQL Server 2022 Developer on EC2 INCREMENTAL adapter
       -> ORACLE|FULL           -> Oracle FULL adapter
       -> ORACLE|INCREMENTAL    -> Oracle INCREMENTAL adapter
       -> ...
```

The exact adapter contract is intentionally deferred until a second real
connector exists. This avoids designing the abstraction around assumptions that
may not hold for timestamp, sequence, SCN, commit-version, or other boundary
types.

## Non-goal

The current project does not add a second database technology only to prove this
extension point. The routing boundary is implemented now; deeper generalization
is deferred until a real second connector requires it.
