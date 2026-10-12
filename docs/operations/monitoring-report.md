# Operational Monitoring MVP

This MVP reads existing terminal **object-level audit**. It does not introduce
a master-run log, pipeline activity, Eventhouse, or scheduled refresh pipeline.

## 1. SQL monitoring views

Execute `scripts/monitoring/01_create_monitoring_views.sql` on the **Fabric
SQL Database** `sqldb_ingestion_control` (DEV). The same three view
definitions are tracked in the Fabric SQL Database Project under `audit/Views/`.

| View | Purpose |
| --- | --- |
| `audit.v_monitor_source_batch` | One row per `batch_id + source_system` with core status counts, summarized status and timings |
| `audit.v_monitor_latest_source` | Latest observed audited batch **per source system**; one row per source |
| `audit.v_monitor_object_history` | Finalized object execution history, including error details and Run ID |

No existing table, stored procedure, connection, watermark or audit record is
modified. Script can be rerun using `CREATE OR ALTER VIEW`.

### Status meaning

`source_status` is a **derived object-outcome summary**, not a Fabric
Master Pipeline run state. MVP count metrics are SUCCESS / FAILED / SKIPPED.
If a terminal audit contains WARN or CANCELLED, those statuses are still
recognized when calculating source status, but do not get separate count
columns. Status precedence: FAILED > CANCELLED > WARN > SUCCESS > SKIPPED.
A run with SUCCESS + SKIPPED is SUCCESS; an all-SKIPPED batch is SKIPPED.

A source's "latest" means the batch with the most recent **audited object
end_time** for that source. Sources with different schedules can therefore
show results from different Batch IDs and times. Keep the timestamps visible;
a previous successful run is not evidence that a new scheduled run succeeded.

Because the current audit writes one row **when an object reaches a terminal
outcome**, these views do not show RUNNING. They can show a partially finalized
batch while other objects still execute. A Master failure before any object
audit, or a failure to persist a terminal audit, will not appear. Refer to
Fabric Monitor / the existing Activator master-failure alert for these cases.

## 2. Power BI

Use **one Power BI Report**, not a separate Power BI Dashboard artifact.
For the initial model, use DirectQuery against the **operational Fabric SQL
Database** and its views so refreshing visuals reads the latest committed
audit. The SQL analytics endpoint is a replicated reporting alternative, but
has eventual-latency semantics; use it instead if the reporting workload
begins to affect the operational database.

Deployable Report and Semantic Model definitions are at
`fabric/IngestionOperations.Report/` and `fabric/IngestionOperations.SemanticModel/`.
The PBIP launcher and setup instructions stay in `powerbi/IngestionOperations/`.
The generated report must be runtime-validated after Git Sync.

## 3. Acceptance checks

1. Latest-source SQL returns one row each for ECOMMERCE and LOGISTICS_VENDOR
   when both have historical audits.
2. A source run's `source_status` and counts agree with the individual
   rows returned by `audit.v_monitor_object_history` for its Batch ID.
3. After a new completed ingestion, use **Refresh visuals** in Power BI
   Service and verify the affected source's last Batch ID and end time change.
4. Apply a source filter and verify object history shows only that source.
5. Confirm the report does **not** claim to display Master RUNNING or
   no-audit failures.

All stored times are UTC. No automatic page refresh is required for MVP.
