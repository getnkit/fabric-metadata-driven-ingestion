# Ingestion Operations — Power BI Report Template

A single-page **Power BI Report** with DirectQuery. The two deployable
artifact definitions are under the workspace Git folder `fabric/`. This
folder retains the optional Power BI Desktop launcher and theme.

**Contents:** Source System filter, four KPI cards, latest source status
table, success/failed/skipped chart, and terminal Object Execution History.
The slicer filters the history using the LatestSource -> ObjectHistory model
relationship. Times are UTC.

## Set up

1. Run (or **rerun**, if previously applied) the updated
   `scripts/monitoring/01_create_monitoring_views.sql` in the operational
   Fabric SQL Database `sqldb_ingestion_control`. The latest version removes
   `warn_count` and `cancelled_count` output columns. Check its SELECT output.
2. The operational Fabric SQL Database server is already set in
   `../../fabric/sm_ingestion_operations.SemanticModel/definition/expressions.tmdl`:
   `6j37c7ougv4uthql2zudf5m3ra-6fcoxgexxg6ejngvdk4amt47k4.database.fabric.microsoft.com`.
   Confirm the database name `sqldb_ingestion_control` and your workspace
   access. No password or access token belongs in Git.
3. **Windows/Desktop route:** open `rpt_ingestion_operations.pbip` in Power BI
   Desktop, sign in using Microsoft Entra/Organizational Account for the
   Fabric SQL Database, verify both DirectQuery views, then publish.
4. **Browser-only route (macOS):** open Fabric workspace > Source control
   and review **Update from Git**. Expect the report and semantic model to be updated/created with
   the new consistent names `rpt_ingestion_operations` and
   `sm_ingestion_operations`, plus
   the intended SQL Database view-definition changes. Verify no unrelated
   pipeline or workspace changes are included before applying.
   This renames the Power BI items while keeping their existing `logicalId`
   values. Review possible rename/conflict prompts carefully; do not delete
   an existing semantic model to force a sync. If validation fails, capture
   the exact error before retrying. After sync, configure credentials
   and inspect visuals.
5. In Power BI Service select **Refresh visuals** after a pipeline run to
   read newly committed results. Automatic Page Refresh is optional and
   capacity-dependent.

## Interpretation / acceptance

- `LatestSource` represents the most recent **audited object batch** per
  Source System; different sources may have different last Batch IDs/times.
- Displayed counts are SUCCESS, FAILED and SKIPPED; WARN/CANCELLED are
  classified in source_status only when they actually appear in audit.
- Source/System selections filter the Object History table.
- The report does **not** show RUNNING, Master failures before object audit,
  or guaranteed completeness while a batch is still executing. Fabric Monitor
  and the existing Activator master-failure alert remain responsible for those.
- Reconcile a new run with `audit.v_monitor_latest_source` and verify the
  updated Batch ID and timestamp after Refresh visuals.

This is a source-controlled report **template**. JSON and field references
were statically validated; Power BI Desktop/Fabric runtime rendering and
SQL credentials have not been tested in this environment. No Eventhouse,
custom visuals, extra pipeline or separate Dashboard item is required.
