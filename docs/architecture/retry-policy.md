# Retry Policy

Use retry according to side-effect semantics, not activity type alone.

| Activity / side effect | Retry | Rationale |
| --- | ---: | --- |
| Read-only Lookup | 2 | Safe to repeat for transient connectivity/runtime failures. |
| Validation stored procedure | 0 | Invalid input is deterministic; retry does not change the result. |
| Audit-only finalizer (`advance_watermark = false`) | 2 | Finalization is idempotent by `pipeline_run_id`; repeated calls do not create duplicate audit rows. |
| State-mutating finalizer (may use `advance_watermark = true`) | 0 | Watermark mutation and semantic conflicts must not be retried blindly. |
| Idempotent cleanup notebook | 1 | Cleanup can be repeated safely, but notebook startup is relatively expensive. |
| Copy to Bronze / final data store | 0 | Repeating a write is not inherently idempotent; partial writes must be compensated before rerun. |\n| SFTP Binary Copy to batch-isolated Landing | 2 | Landing is scoped by `batch_id`, Binary + PreserveHierarchy can safely retry transient transfer failures within the same run, and failed batches are cleaned up after retries are exhausted. |
| Invoke Pipeline | 0 | Child pipelines own their own retry and side-effect handling. |

## Finalizer rule

`control.usp_finalize_ingestion_run` is retry-safe for audit-only calls because it exits when the same `pipeline_run_id` already exists in `audit.ingestion_log`.

Do not apply blind retry to calls that can advance watermark state. A state-changing call can surface semantic failures such as `WATERMARK_CONFLICT`; retrying it could mask the original failure after an audit row has already been committed.


## SFTP Landing exception

The generic Copy rule remains `retry = 0` for direct writes to Bronze or other durable data stores.

`copy_sftp_to_landing` is the explicit exception and uses `retry = 2` with a 30-second interval because the destination is a batch-isolated raw Landing path. Retries occur within the same pipeline execution and therefore keep the same `batch_id`. If all retries are exhausted, the framework performs compensating cleanup of the current Landing batch before finalizing the run as failed.
