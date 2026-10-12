# Ingestion Operations — Power BI Desktop-authored baseline

The official **Power BI Report** (`rpt_ingestion_operations`) and
**Semantic Model** (`sm_ingestion_operations`) are stored under
`fabric/`. Their current PBIR/TMDL definitions originate from the report
manually built in Power BI Desktop and committed from the Fabric workspace
on 2026-10-12. The earlier code-authored report/model definitions and optional
scaffold PBIP launcher/theme have been retired.

## Deploy and inspect

1. Ensure that the monitoring SQL Views exist in `sqldb_ingestion_control`
   by running `scripts/monitoring/01_create_monitoring_views.sql` as needed.
   Their schema definitions are also in the SQL Database Project under
   `fabric/sqldb_ingestion_control.SQLDatabase/audit/Views/`.
2. In Fabric Workspace > Source control > **Update from Git**, review the
   Report/Semantic Model changes carefully; retain the original canonical
   items and their identities. Do not create a second official report.
3. Open `rpt_ingestion_operations`, check connection credentials, and
   **Refresh visuals**. Verify two DirectQuery tables, one relationship, seven
   DAX measures, four KPIs, the Source System slicer, latest summary table,
   status chart, and 10-column Object Execution History.
4. Validate Source System filtering, null exclusion, UTC timestamps with
   seconds, numeric zero Failed Sources, and descending End (UTC) history.

The Semantic Model uses the Fabric SQL Database connection string configured
by Power BI Desktop within its two DirectQuery table partitions; no
password/token is committed. The source connection uses Microsoft Entra
authentication and requires access to the database.

This is **object-level terminal audit monitoring**, not a live Fabric master
pipeline run monitor. It doesn't report RUNNING jobs, failures before any
object audit, or incomplete batches with absolute certainty. See
[monitoring-report.md](../../docs/operations/monitoring-report.md).

For future desktop edits, use Power BI Desktop and export/commit the project's
native PBIR/TMDL definitions to the official `fabric/` paths; do not
maintain separate parallel code-generated visual definitions.
