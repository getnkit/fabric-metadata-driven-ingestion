# Bronze Compensating Cleanup

This runbook documents the framework's automatic compensating cleanup for append-oriented Bronze ingestion.

## Framework invariant

Bronze ingestion is append-only for every successful ingestion execution, regardless of run type.

```text
REGULAR  -> append a new Bronze batch
BACKFILL -> append a new Bronze batch
```

A successful Bronze batch is never deleted, truncated, overwritten, or replaced merely because a later REGULAR or BACKFILL run processes overlapping source data. Each execution preserves its own `_batch_id` / pipeline-run lineage.

The only ingestion-time deletion allowed by this framework is **compensating cleanup of the current failed batch** when a Bronze write may have partially succeeded. That failed batch is not treated as committed Bronze history.

Retention, legal erasure, or other lifecycle-management policies are separate governance/maintenance concerns and are not part of REGULAR/BACKFILL ingestion semantics.

## Why it exists

A Bronze write and the control/audit finalization are not one distributed transaction. A pipeline can fail after rows have already reached Bronze while the watermark/control state remains uncommitted. A blind rerun can then append the same logical input again.

The recovery scope is the pair **(`batch_id`, `pipeline_run_id`)** in the
specific target Delta table. The orchestrator intentionally shares a batch ID
across different configs for correlation; the object controller has its own
pipeline run ID. Both metadata columns are present in the Azure SQL and SFTP
Bronze outputs. Filtering only by batch ID could remove another config's rows
if two configs write to the same target in one orchestrator batch.

## FILE Landing cleanup isolation

An orchestrator batch may include multiple `ingestion_config_id` values
that share a Landing base path (and may target the same Bronze table).
SFTP FULL and INCREMENTAL Landing paths therefore use the leaf scope
`ingestion_date=<date>/ingestion_config_id=<id>/batch_id=<id>/pipeline_run_id=<object_run_id>/`.
Landing cleanup validates these exact trailing segments before recursively
deleting the failed execution's leaf folder; it cannot delete a sibling
config/run folder. The audit `landing_path` points to the same execution
folder used by Copy and the Notebook. Bronze cleanup separately uses the
existing `(_batch_id, _pipeline_run_id)` predicate.

## Reusable component

The framework uses one notebook item:

```text
nb_cleanup_bronze_batch_rows
```

Inputs:

```text
p_workspace_id
p_lakehouse_id
p_target_schema
p_target_table
p_batch_id
p_pipeline_run_id
```

The notebook resolves the target Delta table, counts rows matching **both**
`_batch_id` and `_pipeline_run_id`, deletes only those rows, re-counts that
same object execution, and fails with `BRONZE_CLEANUP_INCOMPLETE` if any
matching rows remain.

The notebook is idempotent: a retry against an already-clean batch succeeds with zero rows removed.

If the target Delta path does not exist because the failed write never created the
Bronze table/path, cleanup is also a successful no-op. The notebook emits
`BRONZE_CLEANUP_NOOP ... reason=TARGET_NOT_FOUND` and returns successfully. Other
read/Delta errors are rethrown rather than treated as absence.

## Automatic trigger contexts

Current active append paths invoke the notebook when a Bronze write activity or
Bronze-writing notebook fails and may have left partial rows:

```text
nb_cleanup_bronze_write_failed
```

Control-only decisions that do not depend on Bronze output are evaluated before
Bronze mutation. If one of those decisions fails, the run is finalized as a
pre-write control failure and no Bronze cleanup is required.

## Success and failure behavior

If cleanup succeeds, the original ingestion failure is finalized with watermark advancement disabled.

If cleanup fails, the run is finalized as FAILED with `BRONZE_CLEANUP_FAILED`, and the pipeline fails explicitly. Do not rerun blindly until the failed batch has been reconciled.

## Audit error-message length contract

The Fabric SQL Database stores `audit.ingestion_log.error_message` as
`NVARCHAR(4000)`; the shared `control.usp_finalize_ingestion_run` parameter
uses the same limit. **Only Finalizer expressions that propagate an Activity
`.error.message`** have the Fabric Data Factory `substring(...,0,4000)`
boundary guard (15 Finalizers across the Personal repo).

- Single Copy, Notebook, or Lookup Activity errors (including error propagation
  through a Switch/If Activity) use
  `@substring(string(activity('some_activity').error.message),0,4000)`.
- A combined **original activity failure + cleanup activity failure** reserves up
  to **1,900 characters for each source error**, then caps the labeled combined
  result at 4,000 so both categories are retained.
- Landing file-count mismatch followed by a cleanup Activity failure retains
  the numeric mismatch description and up to 3,800 characters of cleanup
  `.error.message`, then caps the composed result at 4,000.
- Framework-composed Validation and Routing `concat()` messages **do not use
  `substring()`** under this scoped change. NULL error messages, statuses,
  retry/cleanup dependencies, and watermark behavior remain unchanged.
- Truncation can omit a later stack-trace tail. Inspect the failing Fabric
  Activity run for complete diagnostics.

Acceptance: in DEV, provoke long Copy/Notebook/Lookup errors and cleanup
failures. Confirm terminal audit entries are written; activity-derived
`error_message` values have `LEN(error_message) <= 4000`; both labels remain
visible for combined failures; and failed executions do not advance the watermark.
The implementation has undergone static verification, not Fabric runtime testing.

## Safety boundary

Do not automatically delete Bronze rows after `sp_finalize_success` itself fails.

That stored procedure may have committed the audit/watermark transaction before the client observed the failure. Automatically deleting Bronze after an ambiguous successful finalization could leave committed control state pointing past missing data.

## Verification queries

Audit:

```sql
SELECT TOP 5
    ingestion_log_id,
    ingestion_config_id,
    batch_id,
    pipeline_run_id,
    status,
    processing_lower_bound,
    processing_upper_bound,
    source_row_count,
    target_row_count,
    error_code,
    error_message
FROM audit.ingestion_log
WHERE ingestion_config_id = <config_id>
ORDER BY ingestion_log_id DESC;
```

Watermark:

```sql
SELECT
    ingestion_config_id,
    watermark_field,
    last_watermark_value,
    last_successful_batch_id,
    last_successful_pipeline_run_id
FROM control.pipeline_watermarks
WHERE ingestion_config_id = <config_id>;
```

Bronze batch check:

```sql
SELECT COUNT(*) AS batch_rows
FROM <target_schema>.<target_table>
WHERE _batch_id = '<batch_id>'
  AND _pipeline_run_id = '<object_pipeline_run_id>';
```

For a failed run that completed automatic cleanup, `batch_rows` must be zero and the watermark must remain at the previously committed value.

## Manual fallback

If an operational incident predates the automatic cleanup path, or cleanup itself could not run, reconcile only the failed (`_batch_id`, `_pipeline_run_id`) pair using a Fabric Notebook / Spark Delta operation and verify zero remaining rows before rerun.
