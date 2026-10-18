# Ingestion Operations — Monitoring Report

## Purpose and limits

The **official** Power BI Report `rpt_ingestion_operations` and Semantic
Model `sm_ingestion_operations` are authored in Power BI Desktop and tracked
in `fabric/` as PBIR/TMDL. The Report was subsequently synced back to Fabric
and verified visually/operationally in DEV (2026-10-13).

The report reads **terminal object-level ingestion audit** from the Fabric SQL
Database. It does **not** create a separate master-run audit, Eventhouse,
real-time refresh engine or scheduled report pipeline. It cannot show
RUNNING work, master failures before object audit, or unpersisted audit
outcomes; use Fabric Monitor for those cases. A "latest" audited batch may
be partially complete while other objects are still running.

## SQL views and metric grain

Execute `scripts/monitoring/01_create_monitoring_views.sql` against
`sqldb_ingestion_control`; the identical views are also tracked under
`fabric/sqldb_ingestion_control.SQLDatabase/audit/Views/`.

| SQL view | Grain / purpose |
| --- | --- |
| `audit.v_monitor_source_batch` | One row per **source_system + batch_id**, summarizing terminal object outcomes and timing |
| `audit.v_monitor_latest_source` | **One latest audited batch per source_system**, selected from the batch view |
| `audit.v_monitor_object_history` | One row per finalized object execution, including status, counts, error and Run ID |

These definitions do not alter Control/Watermark state or original audit rows.
Source Status is a **derived object outcome**; it is **not** a master
pipeline run state. Status precedence is
`FAILED > CANCELLED > WARN > SUCCESS > SKIPPED`.
The visual success/failed/skipped counts cover these three statuses only;
WARN/CANCELLED can still affect the summarized Source Status without having
separate chart series.

"Latest" means the source's batch with the latest **audited object end_time**.
Different source systems can display different Batch IDs; a previous
successful batch is not proof that the next scheduled run succeeded.

## Semantic model

- DirectQuery to **operational Fabric SQL Database** (no scheduled Import
  refresh), with `LatestSource` and `ObjectHistory` tables.
- Active single-direction relationship:
  `LatestSource[source_system] (1) -> ObjectHistory[source_system] (*)`.
  Filtering selects *all historical objects from that source*, not just
  the source's latest batch.
- **7 DAX measures**, all on `LatestSource`:
  `Source Systems`, `Failed Sources`, `Objects`,
  `Latest Activity (UTC)`, `Successful Objects`,
  `Failed Objects`, `Skipped Objects`.
- `Failed Sources` counts sources whose **latest audited batch status**
  is FAILED, not the number of failed object executions.
  `Objects` sums counts from each source's latest audited batch.
- The native `Latest Activity (UTC)` measure remains DateTime and is
  formatted without a text-conversion helper. Visual-level
  `source_system is not blank` filters replace the retired
  `Valid Source Option` DAX measure.
- TMDL currently embeds the original DEV SQL Database server/database
  in its DirectQuery partitions: rebind in a **new** workspace by following
  [Environment Rebuild](environment-rebuild.md). Do not use those IDs
  blindly across environments.

## Report page: Operations

The page uses 16:9 layout. The visuals are:

| Section | Content |
| --- | --- |
| Header | `Ingestion Operations`; `Latest Recorded Batch per Source System | All Timestamps in UTC` |
| Slicer | `Source System`, nonblank values, no hardcoded source allowlist |
| KPI cards (4) | `Source Systems`, `Failed Sources`, `Objects`, `Latest Activity (UTC)` |
| Table | `Latest Batch Summary by Source System`: Source System, Status, Objects, Success, Failed, Skipped, Last End (UTC) |
| Clustered bar chart | `Latest Batch Summary by Source System`: Success, Failed, Skipped by Source System, using consistent status colors |
| History table | `Object Execution History`: Source System, Object, Run Type, Status, Source Rows, Target Rows, Duration (s), End (UTC), Error Code, Pipeline Run ID |

The summary Table and Chart sort `source_system` ascending;
Object History sorts `end_time` descending. All displayed timestamps
are UTC with seconds. Slicer and Chart exclude blank Source System directly.
No visual must depend on the names of the two demo sources.

## Pipeline failure notifications (Activator DEV experiment)

Failure notifications are **separate from the Power BI audit report**. The optional Fabric Activator approach watches Fabric pipeline job events for **`pl_ingest_orchestrator` = Failed**, then invokes an operator notification action (such as email or Teams), rather than embedding a notification activity in each child. Source-scoped and all-active runs use the same master pipeline item, but a FAILED run means a failure within **that run's scope**, not every configured source system.

Scheduling and the recipient/channel are environment-specific and not provisioned in Git. To accept an alerting setup, verify the master FAILED event, a FAILED object audit *when an object/config was resolved*, and **actual recipient receipt**. A master failure before object resolution may create no object audit.

**Observed in DEV (2026-10-04):** two master FAILED events were detected, and Activator rule/action activity was observed. **Delivery to the intended recipient inbox was not independently verified.** This proves event detection/action invocation only, not an end-to-end verified notification service.

## Acceptance and follow-up

- DEV screenshot/visual evidence showed **2** Source Systems, **8** Objects,
  **0** Failed Sources across the latest observed batches:
  ECOMMERCE had 6 Objects (1 SUCCESS, 5 SKIPPED);
  LOGISTICS_VENDOR had 2 (1 SUCCESS, 1 SKIPPED).
- Source-specific filtering, no blank slicer/chart category, timestamp
  display, historical sorting and the overall Report layout were reviewed.
- The official Desktop-authored report/model were promoted into canonical
  Git paths and **the user subsequently confirmed** that Fabric Git Sync
  completed and the official Report worked normally. This closes the
  Operational Monitoring UI/implementation phase.
- This evidence does **not** independently certify newest-batch failure
  behavior, every abnormal Pipeline path, fresh-data propagation latency,
  backup recovery, or alert recipient delivery.
- When re-creating DEV, check SQL views, DirectQuery credentials, the
  Slicer interaction and metric counts, not only that PBIR files import.
  See [Environment Rebuild](environment-rebuild.md).
- For optional operator notifications and the still-unverified delivery evidence, see [Pipeline failure notifications](#pipeline-failure-notifications-activator-dev-experiment).

### Source of truth

- `fabric/rpt_ingestion_operations.Report/` — PBIR visual/layout definition.
- `fabric/sm_ingestion_operations.SemanticModel/` — DAX, M partitions and
  relationships.
- `scripts/monitoring/01_create_monitoring_views.sql` — runnable SQL views.
- `fabric/sqldb_ingestion_control.SQLDatabase/audit/Views/` — SQL Project views.
For a new workspace, create the three monitoring views, import/sync both
canonical Fabric artifacts, rebind the model's two DirectQuery partitions to
the new SQL Database, configure Entra credentials and verify the four KPI
cards, Source System slicer, latest-batch summary and 10-column history.
See [Environment Rebuild](environment-rebuild.md) for the deployment and
connection/ID checklist. For future edits, use Power BI Desktop and commit
the native PBIR/TMDL definitions to the canonical `fabric/` paths.
