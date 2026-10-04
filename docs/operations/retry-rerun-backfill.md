# Retry, Rerun, and Backfill Semantics

## Decision

Framework `run_type` is limited to:

```text
REGULAR
BACKFILL
```

`RERUN` is not a framework run type. Microsoft Fabric Retry/Rerun is an execution-recovery feature and is separate from framework data-processing intent.

Two independent dimensions are preserved for every run:

```text
load_strategy = FULL | INCREMENTAL   # persistent dataset/config metadata
run_type      = REGULAR | BACKFILL   # per-execution intent
```

A BACKFILL does not change the configured `load_strategy`.

## REGULAR

`REGULAR` is the normal operational execution mode.

```text
REGULAR + FULL
  -> read the configured full current source scope
  -> no requested LOW/HIGH

REGULAR + INCREMENTAL
  -> LOW  = committed operational watermark
  -> HIGH = source/run boundary captured for this execution
  -> advance operational state only after successful finalization
```

## BACKFILL

`BACKFILL` is an intentional recovery/repopulation execution rather than the normal processing cycle.

Current V1 semantics are:

```text
BACKFILL + FULL
  -> reread the full currently available source scope
  -> no requested LOW/HIGH
  -> append a new Bronze batch

BACKFILL + INCREMENTAL
  -> process an explicitly requested historical LOW/HIGH range
  -> never advance the operational watermark/checkpoint
  -> append a new Bronze batch
```

A FULL BACKFILL may physically read the same source rows as a REGULAR FULL run. The difference is execution intent and lineage: the BACKFILL run is performed to repopulate/recover data and is audited as BACKFILL.

The current V1 FULL BACKFILL does not select a historical point-in-time snapshot. If a future source requires a historical full snapshot, add an explicit source-appropriate selector such as `data_date`, snapshot ID, source version, or timestamp rather than overloading LOW/HIGH.

## Bronze invariant

Bronze is append-only for every successful REGULAR or BACKFILL execution.

A later run never deletes, truncates, overwrites, or replaces a previously successful Bronze batch merely because the source scope overlaps. Each execution preserves its own `_batch_id` and pipeline-run lineage.

The only ingestion-time deletion allowed is compensating cleanup of the current failed batch when a Bronze write may have partially succeeded.

## Audit semantics

`audit.ingestion_log` keeps both dimensions:

```text
run_type      = REGULAR | BACKFILL
load_strategy = FULL | INCREMENTAL
```

Examples:

```text
REGULAR  + FULL
REGULAR  + INCREMENTAL
BACKFILL + FULL
BACKFILL + INCREMENTAL
```

Processing-boundary fields are populated only when relevant to the selected scope. In the current V1 contract, BACKFILL + INCREMENTAL records requested LOW/HIGH while BACKFILL + FULL does not.

## Platform execution recovery

The supported operational entry point remains `pl_ingest_orchestrator`. Direct manual execution/retry of dispatcher, controller, router, adapter, or loader pipelines is not part of the supported contract.

For deterministic recovery from a failed REGULAR run, prefer a new top-level REGULAR execution unless the operator intentionally needs BACKFILL semantics.

Do not add a framework `REPROCESS` type until a concrete requirement needs a distinct data-replacement policy.
