# Retry Policy

Use retry according to side-effect semantics, not activity type alone.

| Activity / side effect | Retry | Rationale |
| --- | ---: | --- |
| Read-only Lookup | 2 | Safe to repeat for transient connectivity/runtime failures. |
| Validation stored procedure | 0 | Invalid input is deterministic; retry does not change the result. |
| Audit-only finalizer (`advance_watermark = false`) | 2 | Finalization is idempotent by `pipeline_run_id`; repeated calls do not create duplicate audit rows. |
| State-mutating finalizer (may use `advance_watermark = true`) | 0 | Watermark mutation and semantic conflicts must not be retried blindly. |
| Idempotent cleanup notebook | 1 | Cleanup can be repeated safely, but notebook startup is relatively expensive. |
| Copy | 0 | Repeating a write is not inherently idempotent. |
| Invoke Pipeline | 0 | Child pipelines own their own retry and side-effect handling. |

## Finalizer rule

`control.usp_finalize_ingestion_run` is retry-safe for audit-only calls because it exits when the same `pipeline_run_id` already exists in `audit.ingestion_log`.

Do not apply blind retry to calls that can advance watermark state. A state-changing call can surface semantic failures such as `WATERMARK_CONFLICT`; retrying it could mask the original failure after an audit row has already been committed.
