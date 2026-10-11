# Ingestion Operations — Power BI Report Template

A single-page **Power BI Report** with DirectQuery. The report is outside
`fabric/` until it is configured and runtime-tested, so it does not affect
existing Data Pipeline Git Sync.

**Contents:** Source System filter, four KPI cards, latest source status
table, success/failed/skipped chart, and terminal Object Execution History.
The slicer filters the history using the LatestSource -> ObjectHistory model
relationship. Times are UTC.

## Set up

1. Run `scripts/monitoring/01_create_monitoring_views.sql` in the operational
   Fabric SQL Database `sqldb_ingestion_control` and check its SELECT output.
2. In `IngestionOperations.SemanticModel/definition/expressions.tmdl`,
   replace `REPLACE_WITH_FABRIC_SQL_SERVER.database.windows.net` with
   the operational database's SQL server name. Keep the database name or edit
   it if needed. No password or access token belongs in Git.
3. **Windows/Desktop route:** open `IngestionOperations.pbip` in Power BI
   Desktop, sign in using Microsoft Entra/Organizational Account for the
   Fabric SQL Database, verify both DirectQuery views, then publish.
4. **Browser-only route (macOS):** you can create the semantic model/report
   in Fabric directly using these views and the layout in this template.
   Alternatively, after editing the server placeholder, review moving the
   .SemanticModel and .Report folders into your Fabric Git-integrated workspace
   path; check connection/credential binding and visuals after syncing.
   Do not move unconfigured items into a working workspace.
5. In Power BI Service select **Refresh visuals** after a pipeline run to
   read newly committed results. Automatic Page Refresh is optional and
   capacity-dependent.

## Interpretation / acceptance

- `LatestSource` represents the most recent **audited object batch** per
  Source System; different sources may have different last Batch IDs/times.
- Aggregated status precedence: FAILED > CANCELLED > WARN > SUCCESS > SKIPPED.
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
