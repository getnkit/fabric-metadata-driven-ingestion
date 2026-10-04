# Retry, Rerun, and Backfill Semantics

## Decision

Framework `run_type` is limited to:

```text
REGULAR
BACKFILL
```

`RERUN` is not a framework run type.

## REGULAR

`REGULAR` is the normal operational execution mode.

For REGULAR execution, the configuration's `load_strategy` determines how the
source is read:

```text
REGULAR + configured FULL
REGULAR + configured INCREMENTAL
```

An INCREMENTAL REGULAR run derives its processing window from committed
operational state. A FULL REGULAR run executes the configured full-load behavior.

## BACKFILL

`BACKFILL` is a separate execution intent for an explicitly requested
historical scope. It is not classified as FULL or INCREMENTAL.

The current V1 runtime contract represents the historical scope with:

```text
requested lower_bound
requested upper_bound
```

Pattern-specific adapters decide how those boundaries are applied. Current
implementations include:

- DATABASE: historical LOW/HIGH window against the configured watermark field.
- FILE/SFTP: historical LOW/HIGH window against source file Last Modified time.

A future source may use a different backfill selector such as `data_date`,
snapshot ID, source version, or another source-specific historical reference.
That would extend the backfill scope contract rather than create a new
FULL/INCREMENTAL classification for BACKFILL.

## Processing-state rule

BACKFILL never advances the operational watermark/checkpoint.

Operational state represents forward REGULAR processing. Moving that state
because of a historical BACKFILL could make the next REGULAR run skip data or
move backward incorrectly.

A BACKFILL scope may overlap data processed successfully before. Bronze is
append-oriented, so a new backfill creates new batch/run lineage rather than
deleting or replacing an earlier successful batch.

## Audit semantics

For REGULAR runs, `audit.ingestion_log.load_strategy` records the configured
FULL or INCREMENTAL strategy.

For BACKFILL runs, `load_strategy` is stored as NULL because BACKFILL is its own
run intent. The historical scope is represented by the processing-boundary
fields and related source metadata.

## Platform execution recovery

Microsoft Fabric Retry/Rerun is an execution-control feature and is separate
from framework data-processing intent:

```text
Fabric Retry/Rerun
!= framework run_type
```

The supported operational entry point remains `pl_ingest_orchestrator`.
Direct manual execution/retry of dispatcher, controller, router, adapter, or
loader pipelines is not part of the supported contract.

For deterministic recovery, prefer a new top-level REGULAR execution after a
failed REGULAR run. The committed watermark remains the source of truth.

The framework keeps batch-scoped compensating cleanup for failed Bronze writes.
It does not perform destructive LOW/HIGH window cleanup against previously
successful batches.

## Future reprocessing

Do not add `REPROCESS` until a concrete requirement needs intentional
replacement/deduplication of data that was already processed successfully.
That behavior requires an explicit target policy rather than another synonym
for execution retry.
