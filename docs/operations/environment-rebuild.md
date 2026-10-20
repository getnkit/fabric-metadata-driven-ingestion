# Environment Rebuild — Fresh DEV From Git

**Goal:** Recreate a functional DEV environment for **Metadata-Driven Pipelines in Microsoft Fabric** after losing
or retiring a workspace. This is a fresh-install runbook, not a backup/restore procedure. It cannot recover
historical Bronze, audit, or watermark state from Git alone.

- **Supported scope:** Fabric SQL Database, Bronze Lakehouse, Variable Library,
  12 Data Pipelines, 3 Notebooks, 2 Power BI artifacts, optional Activator, and
  optional EC2 SQL Server/SFTP demo sources.
- **Entry point:** `pl_ingest_orchestrator`; do not run child pipelines directly.
- **Source of truth:** `fabric/` for Fabric item definitions and
  `scripts/control/` for safe SQL bootstrap. Use
  [RUN_ORDER](../../scripts/RUN_ORDER.md) for detailed metadata seed semantics.
- **Do NOT use this runbook to overwrite a populated environment.** Stop if the
  target already has meaningful audit, watermark, Bronze or source data.

## A. Recoverability contract

| Asset | Stored in Git? | Rebuild outcome |
| --- | --- | --- |
| Pipeline/Notebook/Library/Report/Semantic Model definitions | Yes, `fabric/` | Import definitions, then rebind environment |
| Control/Audit SQL schema, procedures, monitoring views | Yes, `fabric/...` and `scripts/` | Create fresh empty database schema |
| Demo ingestion configs, sample source generators, static CSVs | Yes | Recreate DEV fixtures and *initial* watermarks |
| EC2 SQL Server + SFTP service configuration | Yes, `infra/source/` | Provision a fresh host and recreate demo data |
| Cloud Connections, credentials, permissions, live Fabric item IDs | **No** | Recreate/re-authorize manually |
| Historic `control.pipeline_watermarks`, `audit.ingestion_log` | **No** | **Not recovered** without separately verified backup |
| Existing Bronze Delta rows and Lakehouse Files | **No** | **Not recovered** by Git sync |
| Original SQL Server database files, remote SFTP uploads, SFTP private host key | **No** | Recreate demo data; restoring original state needs separate backups |
| Historic schedules, notification recipient, test results | Not guaranteed | Reconfigure explicitly where used |

**New DEV** means resetting processing to demo initial state and creating
new Batch/Run IDs. **Disaster recovery with historical continuity** needs
consistent, separately verified backups of SQL Control/Audit state, Bronze
Delta/Files, source systems and credentials, plus an approved reconciliation
plan; these are not provided by this repository. Never describe a fresh
install as recovery of production state.

## B. Readiness / inventory (complete before changing anything)

1. Select a Git **commit/tag** to deploy; for an immutable release prefer a
   reviewed release tag. Clone that revision locally; record its SHA.
2. Provide a Fabric-capable tenant, enabled capacity, permission to create a
   workspace/items/connections, and Git integration authorization.
3. Choose a **new/empty** DEV workspace. Do not point Git at a working PROD
   workspace or run destructive DEV reset scripts against any valuable data.
4. Decide which sources you will rebuild:
   - **Minimal demo:** `sql_ecommerce_db` plus SFTP Logistics fixture.
   - **Optional benchmark:** separate `sql_benchmark_db` and 10M-row tables.
5. Maintain this **private**, uncommitted deployment worksheet:

| Value to record | Where obtained |
| --- | --- |
| New Fabric workspace ID | Workspace URL `/groups/<workspace-id>/` |
| `sqldb_ingestion_control` item ID | SQL Database item URL/details |
| `lh_ecommerce_bronze` item ID | Lakehouse item URL/details |
| Control SQL Database Fabric Connection ID | Manage connections / activity Connection |
| Pipeline Invoke Connection ID | Manage connections / Invoke activity |
| Notebook Execution Connection ID | Manage connections / Notebook activity |
| Source SQL Server Connection ID | Fabric SQL Server connection |
| Source SFTP Connection ID + host key fingerprint | SFTP connection / new EC2 host |
| Target Lakehouse Connection ID | Lakehouse connection |
| Power BI SQL server and database names | New Fabric SQL Database **connection string** |

These are *different namespaces*: workspace/item GUIDs are not Connection
GUIDs. Save any credentials in an appropriate secret store, **never Git**.
Do not reuse IDs from the previous DEV workspace even if the names match.

## C. Create optional demo source infrastructure

**If rebuilding the demo sources:** provision an adequately sized Ubuntu EC2 host with Docker/Compose and tightly
scoped security-group access (SSH 22, SQL Server 1433, SFTP 2222 as applicable; no blanket `0.0.0.0/0` ). Follow the
[source infrastructure runbook](../../infra/source/README.md) for fresh-host setup, the named
`fabric_sqlserver_data` volume, SFTP host key, private `.env` , Compose commands and fixture uploads. Use new
secrets; do not commit them.

Then follow [RUN_ORDER section C](../../scripts/RUN_ORDER.md#c-optional-dev-demo-source) to create
`sql_ecommerce_db` , execute the three source SQL scripts with the correct SQL client/`GO` behavior, and check
expected row counts. Upload the CSV fixtures while preserving `movements/YYYY/MM/` subfolders; FILE incremental
selection uses the **remote SFTP Last Modified** timestamp, not a filename or CSV event timestamp.

**If retaining an existing EC2 host:** follow the infrastructure README's **Existing DEV instance** procedure. Do
not replace its `.env` , regenerate the SFTP host key, overwrite existing SQL volumes, or run
`docker compose down -v` .

Before creating Fabric connections, verify source SQL read-only access, row counts, remote SFTP file listing and the SFTP host-key fingerprint.

## D. Create the Fabric workspace and import definitions

1. Create/connect the fresh workspace and configure **Settings > Git integration**
   for repository `getnkit/fabric-metadata-driven-pipelines` (after the GitHub rename), the desired
   branch, and **Git folder `fabric`**. Do **not** leave the folder blank:
   the Fabric item definitions live under `fabric/`, not the repository root.
   Prefer a dedicated `rebuild/<environment>` branch based on the selected
   baseline so DEV-specific edits cannot accidentally affect `main`.
   Inspect the initial **Update from Git** preview before importing items.
   If desired items are unsupported or fail to materialize, create the
   missing item in Fabric by hand and reconcile against its tracked definition;
   do not assume a Git commit alone deploys every resource.
2. Import/sync the tracked items under `fabric/`:
   - `sqldb_ingestion_control.SQLDatabase` (Control/Audit plane)
   - `lh_ecommerce_bronze.Lakehouse` (empty target; **no Bronze rows**)
   - `vl_ingestion_connections.VariableLibrary`
   - **12** `*.DataPipeline` items and **3** `*.Notebook` items
   - `sm_ingestion_operations.SemanticModel` and
     `rpt_ingestion_operations.Report`
   - `act_ingestion_monitoring.Reflex` only if implementing optional alerts.
3. Verify item *names and types*, record the **new** workspace/SQL DB/Lakehouse
   IDs in the worksheet and check ownership/permissions.
4. Review
   `fabric/sqldb_ingestion_control.SQLDatabase/Security/` before deployment:
   it contains a **prior-workspace Microsoft Entra principal and SID**.
   Do not blindly apply that security object in a new tenant. Prefer the
   fresh SQL bootstrap in section E for schema creation and provision
   permissions appropriate to the new environment. Resolve any Git SQL
   Database Project deployment/security conflict before continuing.

**Important reference semantics:** same-workspace Invoke Pipeline and
Notebook targets in `pipeline-content.json` use logical item IDs matching
their tracked `.platform` files. These are **not** the five runtime
Connection GUID variables. Preserve the logical item identities when
restoring by Git, and *inspect/reselect targets in the Fabric designer* if
the new workspace does not automatically resolve them. Do not globally
replace every GUID in JSON.

## E. Bootstrap SQL Control/Audit and monitoring views

In the **new, empty** `sqldb_ingestion_control` Fabric SQL Database, execute:

```text
scripts/control/01_create_control_schema.sql
scripts/control/02_create_control_procedures.sql
scripts/control/99_verify_control_plane.sql
scripts/monitoring/01_create_monitoring_views.sql
```

Verify **four** tables
(`control.connection_settings`, `control.ingestion_config`,
`control.pipeline_watermarks`, `audit.ingestion_log`), the
`control.v_pipeline_watermarks` view, **two** control procedures, and
**three** `audit.v_monitor_*` views. The `99` script checks structural
constraints/indexes and is not a historical state restore or a full schema
diff. Re-run `99` after seed data as well.

If Git Sync has already applied the SQL Project schema, inspect the
deployed objects and compare with source definitions; these bootstrap scripts
are non-destructive and procedures/views use `CREATE OR ALTER`. Do **not**
run `scripts/dev/00_reset_control_plane.sql` as a normal rebuild step.

## F. Create Fabric Connections and rebind IDs

Connections and grants are **not** recreated by `fabric/` definitions.
Create and **Test connection** for each required resource under Fabric
**Manage connections and gateways** (UI names may vary):

| Purpose | Expected logical name/reference | Where it is consumed |
| --- | --- | --- |
| Fabric Control SQL Database | Control SQL connection | Variable Library + SQL Lookup/SP |
| Same-workspace Pipeline invocation | Invoke Pipeline connection | Variable Library + Invoke activities |
| Same-workspace Notebook execution | Notebook execution connection | Variable Library + Notebook activities |
| E-commerce source SQL Server | `cn_sql_server_ecommerce` / `SQL_SERVER_ECOMMERCE` | SQL seed `03`, Copy |
| Logistics SFTP source | `cn_sftp_logistics_vendor` / `SFTP_LOGISTICS_VENDOR` | SQL seed `03`, Copy |
| Bronze Lakehouse sink | `LH_ECOMMERCE_BRONZE` (logical metadata ref) | SQL seed `03`, Copy |
| Optional benchmark SQL Server | `SQL_SERVER_BENCHMARK` | Optional seed/scenario |

Use a dedicated read-only SQL login for the source; use the appropriate
Fabric/Entra identity for the Control SQL DB; give users and connections the
necessary resource permissions. Update the source host, SQL TLS/firewall
allowlist, SFTP credentials and new SFTP server fingerprint as appropriate.

### F1. Configure the **five String** Variable Library values

Open `vl_ingestion_connections` in the **new workspace**, select the
**active** value set (normally Default), and replace *all* old workspace
values with the worksheet values:

| Variable | Set to |
| --- | --- |
| `ingestion_control_connection_id` | **new Control SQL Fabric Connection GUID** |
| `ingestion_control_workspace_id` | **new Control SQL workspace GUID** |
| `ingestion_control_item_id` | **new Control SQL Database item GUID** |
| `pipeline_invoke_connection_id` | **new Invoke Pipeline Connection GUID** |
| `notebook_execution_connection_id` | **new Notebook execution Connection GUID** |

The committed Library currently includes **old DEV GUIDs as defaults**.
Treat them as **stale in a new workspace**. Never attempt a run before
replacing/validating all five. A newly imported Library initially uses
its **Default** value set; the active-set selection is workspace state,
whereas Default values are stored in Git. After rebinding, review the
Source control diff and do not Commit new environment GUIDs to `main`.
Check each pipeline's Library variables bindings rather than hardcoding
individual pipeline parameters. See
[Variable Library binding contract](variable-library-environment-binding.md).

### F2. Check pipeline/notebook graph

Use the canonical [architecture graph](../architecture/framework-overview.md#orchestration-and-routing) rather than
maintaining another copy of the hierarchy here. The restored workspace should contain **12 pipelines and 3
notebooks**. Inspect **every** Invoke Pipeline and Notebook target in Fabric: names must resolve in the new
workspace. Specifically confirm that the SQL Server INCREMENTAL adapter invokes its Loader and that incremental
success-finalization failure (not FULL) can invoke `pl_ingest_incremental_finalize_recovery` .

Verify all three Notebook targets: `nb_load_file_landing_to_bronze` , `nb_cleanup_bronze_batch_rows` , and
`nb_cleanup_landing_batch_files` . Also check Copy Connections, SQL metadata's Lakehouse workspace/item references,
and Notebook/Lakehouse attachments. **Rebinding Variable Library values alone is not enough** to fix these targets
or Power BI's SQL source.

### F3. Seed fresh DEV logical connection settings

Use a **local execution copy** of `scripts/control/03_seed_connection_settings.sql` and supply all five required,
non-NULL **new-workspace** source/target Connection and Lakehouse IDs.
[RUN_ORDER section D](../../scripts/RUN_ORDER.md#d-optional-dev-demo-control-metadata) is the canonical list of seed
input variable names, logical references, and seed safety rules. Keep the optional benchmark Connection ID `NULL`
unless testing the benchmark.

Run in the new Control SQL Database:

```text
scripts/control/03_seed_connection_settings.sql
scripts/control/04_seed_ingestion_metadata.sql
scripts/control/99_verify_control_plane.sql
```

Expect six active E-commerce and two active Logistics configs; FULL has no incremental checkpoint. Verify config
IDs, connections and initial state before starting any pipelines. **Never commit private GUID/password
substitutions.** Re-running demo seeds into a populated environment does **not** restore historic watermarks/audits;
review its possible configuration updates first. Optional benchmark installation is documented in
[RUN_ORDER section F](../../scripts/RUN_ORDER.md#f-optional-performance-benchmark-separate) .

## G. Rebind operational Power BI

The official Report and Semantic Model are in
`fabric/rpt_ingestion_operations.Report/` and
`fabric/sm_ingestion_operations.SemanticModel/`. They use two
**DirectQuery** partitions over `audit.v_monitor_latest_source` and
`audit.v_monitor_object_history`, plus one active `source_system`
relationship and **seven** DAX measures.

**Known portability issue:** the checked-in Power BI model currently
embeds the previous DEV Control SQL **server and database names** in
these files:

```text
fabric/sm_ingestion_operations.SemanticModel/definition/tables/LatestSource.tmdl
fabric/sm_ingestion_operations.SemanticModel/definition/tables/ObjectHistory.tmdl
```

For a **new** SQL Database, obtain its actual SQL server/database names
from the SQL Database **Connection string** and replace the two
`Sql.Database(server, database)` arguments (prefer editing the model
through Power BI Desktop or an appropriately reviewed TMDL change).
Ensure both partitions point to the **same new** Control SQL Database;
configure OAuth/Microsoft Entra credentials and read access in Fabric.
Commit the reviewed environment-specific change on the appropriate
branch—otherwise future Git Updates can overwrite manual rebinding.

Verify Report `definition.pbir` targets
`../sm_ingestion_operations.SemanticModel`. Open the deployed
`rpt_ingestion_operations`, refresh visuals, test Slicer, KPI counts,
latest-batch summary, and Object Execution History with `End (UTC)`
descending. The Report is based on **terminal object audits** only:
no guaranteed master RUNNING state or failures before object audit.

## H. Minimum rebuild verification and sign-off

Check these **after all rebindings**. Record new environment/run IDs
privately and capture screenshots only when useful.

- [ ] Git/Fabric imported the **intended** items and matched target names;
      any Git sync warnings or unresolved references are cleared.
-  [ ] `01 -> 02 -> 99` passed (including trusted constraints, keys/indexes and two procedures); all three audit
  monitoring views query. On an existing environment, compare SQL Project schemas before upgrading: `01` does not
  migrate them.
- [ ] Source SQL row counts and SFTP fixture listing are correct; all
      required Fabric Connections **Test connection** successfully.
- [ ] All five active Library GUID values are from the **new** workspace;
      no missing binding or wrong Invoke/Notebook target.
- [ ] `control.connection_settings` resolves source and Bronze references;
      metadata lists six E-commerce and two Logistics active configs.
- [ ] Run `pl_ingest_orchestrator` with `p_run_requests = []` and blank
      `p_source_system`. Verify all eight object terminal audits, Bronze
      outputs, correct source/target counts, and expected checkpoint
      advancement for nonempty incremental runs.
- [ ] Run the same scope again: verify incremental no-new-data paths
      report `SKIPPED` without watermark advancement or an unnecessary
      Bronze append. FULL loads have different repeat semantics.
- [ ] Source-scope request `p_source_system = "ECOMMERCE"` works;
      empty active scope fails with `NO_ACTIVE_CONFIGS` as designed.
- [ ] Validate selected error/cleanup/backfill cases **when releasing the
      rebuilt environment**; static Git checks do not prove these paths.
      Refer to [RUN_ORDER section E](../../scripts/RUN_ORDER.md) and
      [retry/rerun/backfill](retry-rerun-backfill.md).
- [ ] DirectQuery Report shows expected Source Systems, Success/Failed/
      Skipped, timestamps (UTC seconds), Slicer filtering, and recent
      Object History; compare SQL Audit if a visual result differs.
- [ ] If Activator is used, rebind its pipeline job source and notification
      destination separately and verify delivery. Alerting is optional;
      [the DEV alerting evidence and limitations](monitoring-report.md#pipeline-failure-notifications-activator-dev-experiment) still apply.

**Release gate:** mark the fresh DEV rebuild verified only after runtime
checks succeed. A document/Git review alone is **not** a tested recovery.

## I. Failure troubleshooting and guardrails

| Symptom | Check first |
| --- | --- |
| `MISSING_RUNTIME_BINDING` | Five Variable Library strings, active value set, pipeline Library references |
| Lookup/SP unauthorized or cannot find SQL item | Control SQL connection + workspace ID + SQL item ID + permissions |
| Invoke or Notebook unauthorized / target missing | Invoke/Notebook Connection, target name/ID, item rights, Git remapping |
| SQL Server / SFTP Copy cannot connect | Remote service + port/CIDR + credentials + SFTP host key / TLS |
| Missing metadata or `NO_ACTIVE_CONFIGS` | Seeds `03/04`, active configs, source scope |
| Wrong/no Bronze data | Lakehouse Connection/item/workspace IDs in `control.connection_settings`, sink rights, Notebook bindings |
| Power BI cannot see new data | Embedded old SQL server/database, OAuth credentials, DirectQuery, SQL views |
| Old audit/watermark missing | **Expected** for fresh DEV; restore only from independent data/state backup |

## J. Repo navigation

- [Starter Kit baseline](../../scripts/RUN_ORDER.md) — existing detailed
  install semantics and optional benchmark.
- [Source infrastructure](../../infra/source/README.md) — fresh EC2,
  existing host, SSH/upload/SFTP particulars.
- [Variable Library](variable-library-environment-binding.md) — exact runtime
  connection-variable contract.
- [SQL Control Plane guardrails](../guides/control-plane.md#sql-enforced-guardrails) — enforced constraints and non-destructive install behavior.
- [Operational monitoring](monitoring-report.md) — report limitations
  and metrics.
- [Run request contract](run-request-examples.md) — REGULAR/BACKFILL,
  scoped and explicit requests.
