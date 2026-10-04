# Retry, Rerun, and Backfill Semantics

## Decision

Framework `run_type` is limited to:

```text
REGULAR
BACKFILL
```

`RERUN` is not a framework run type.

## Meaning

`REGULAR` performs normal forward ingestion from the currently committed
watermark. If a REGULAR execution fails before successful finalization, the
watermark does not advance; the next top-level REGULAR execution starts again
from the committed state.

`BACKFILL` processes one explicitly requested historical LOW/HIGH interval.
It never advances the operational watermark.

A BACKFILL interval may overlap an interval that was processed successfully
before. Bronze is append-oriented, so a new backfill creates a new batch/run
lineage rather than deleting or replacing an earlier successful batch.

## Current incremental backfill support

The implemented incremental adapters use explicit LOW/HIGH boundaries for
BACKFILL:

- Azure SQL DATABASE + INCREMENTAL uses the requested relational watermark window.
- SFTP FILE + INCREMENTAL uses the requested source-file Last Modified window.

REGULAR runs continue to derive their boundaries from committed operational
state. BACKFILL runs do not update that state.

FULL + BACKFILL is not rejected by the generic controller. Historical snapshot
selection is source-specific and must be represented by the source/configuration
when a true historical snapshot is required.

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
