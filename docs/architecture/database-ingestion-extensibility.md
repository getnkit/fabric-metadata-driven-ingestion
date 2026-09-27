# Database Ingestion Extensibility

## Status

Accepted for the current blueprint.

## Current architecture

```text
pl_master_ingestion
  -> pl_ingest_object
      -> DATABASE|LAKEHOUSE|INCREMENTAL
          -> pl_ingest_database_incremental
              -> source_connection_type
                  -> AZURE_SQL
                      -> pl_ingest_azure_sql_incremental
      -> DATABASE|LAKEHOUSE|FULL
          -> pl_ingest_database_full
              -> source_connection_type
                  -> AZURE_SQL
                      -> pl_ingest_azure_sql_full
```

The DATABASE pipelines are intentionally thin connector routers. Their purpose is
to keep physical database technology out of the pattern-level object router.

## Framework-owned behavior

The framework owns semantics that must stay consistent across database vendors:

- REGULAR / RERUN / BACKFILL behavior
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

## Extension rule

When a second database connector such as Oracle, SQL Server, or PostgreSQL is
implemented, add it behind the DATABASE connector router first.

Do not permanently clone framework semantics across vendor pipelines. Compare the
two real implementations and extract common database orchestration only where the
shared contract is proven.

The likely future shape is:

```text
pl_ingest_database_incremental
  -> common database state/boundary orchestration
  -> connector adapter
       -> Azure SQL
       -> Oracle
       -> ...
  -> common validation/finalization
```

The exact adapter contract is intentionally deferred until a second real
connector exists. This avoids designing the abstraction around assumptions that
may not hold for timestamp, sequence, SCN, commit-version, or other boundary
types.

## Non-goal

The current project does not add a second database technology only to prove this
extension point. The routing boundary is implemented now; deeper generalization
is deferred until a real second connector requires it.
