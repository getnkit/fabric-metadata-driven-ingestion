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
`fabric/rpt_ingestion_operations.Report/` and `fabric/sm_ingestion_operations.SemanticModel/`.
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

## 4. Visual refinement (2026-10-12)

- Zero-fill DAX count KPIs (especially Failed Sources). Retain semantic counts.
- Show UTC date plus hour/minute for model timestamps; source SQL values stay intact.
- Use SUCCESS green / FAILED red / SKIPPED gray for fixed chart measures.
- Source slicer blank category remained after an invalid IsBlank PBIR attempt;
  root cause may be model relationship's synthetic blank member.
- Fit the source table and chart vertically; enlarge history, set column widths,
  sort end time newest first, and preserve complete Pipeline Run IDs.
- After Fabric Git sync, validate slicer filtering, zero KPI, chart colors, UTC
  time formatting, correct status mapping and history sorting. Static checks
  do not establish runtime behavior.

## 5. Compact operations view (2026-10-12)

- Header now states only **latest recorded batch per source** and **UTC**;
  descriptions of status precedence remain in this engineering note rather
  than on the dashboard canvas.
- Source System slicer uses a **measure-based visual filter** named
  `Valid Source Option` (1 for a nonblank source label). This preserves
  dynamic discovery of newly onboarded sources, unlike a hardcoded two-source
  allowlist. The slicer needs DEV runtime confirmation that a synthesized
  relationship blank is hidden and it still cross-filters Object History.
  In Power BI, no selected slicer value means all sources; (Blank) is not All.
- KPI measure `Failed Sources` now returns a true numeric integer via
  `COALESCE(SUMX(LatestSource, IF(source_status = "FAILED", 1, 0)), 0)` with
  model format `0`. This avoids the prior `FORMAT()` conversion to text and
  counts failed **sources**, not failed objects. Verify 0 when neither source
  has latest-batch status FAILED, and 1 when exactly one latest source is FAILED.
  `Objects` still sums object counts from latest source batches. `Last Activity`
  formats the maximum audited end time as `dd MMM yyyy HH:mm` (source timestamps
  already UTC); the original DateTime measure remains for analytical use.
- Longer last-activity card and a fixed callout font size avoid truncation.
  Taller textboxes avoid internal scrollbars. History source names have wider
  columns; explicit sort and full pipeline run IDs are retained.
- Three chart series use explicit status colors by measure queryRef to avoid
  depending on base-theme palette propagation during Fabric Git import.
- No SQL View, audit/history data, connection, pipeline or state-management
  semantics changed. Check rendering, measure values, source slicer filtering,
  no title scrollbars, UTC time, and column width after Fabric Sync. **Static
  PBIR JSON checks do not prove Report import or runtime behavior.**
