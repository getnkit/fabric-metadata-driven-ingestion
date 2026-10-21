# Control Plane and Ingestion Configuration

Fabric SQL Database `sqldb_ingestion_control` keeps source configuration, connection references, checkpoints, and object-run audits separate from physical ingestion logic.

This guide explains the four implemented Control/Audit tables and their DEV examples. SQL Server and SFTP are
supported; this is not a data-contract system or an API, CDC, or streaming implementation.

For the execution path that reads this metadata, continue with [Pipeline Orchestration](pipeline-orchestration.md).

## 1. What is stored in the Control Plane?

| Table | What it stores | When it is used |
| --- | --- | --- |
| `control.connection_settings` | Logical source and target connection references, their types, and JSON connection settings | The Object Controller resolves the source and target |
| `control.ingestion_config` | Source object, ingestion pattern, load strategy, target, and source-specific options | The Orchestrator selects objects; the Object Controller resolves each configuration |
| `control.pipeline_watermarks` | Last successfully committed incremental checkpoint for a configuration | The INCREMENTAL adapter reads LOW; successful REGULAR finalization may advance it |
| `audit.ingestion_log` | One terminal result per object Pipeline Run ID, with counts, boundaries, status, and errors | Operations and troubleshooting after object execution |

These are SQL Control/Audit tables, not Bronze business tables. The sample SQL schema is defined in
[01_create_control_schema.sql](../../scripts/control/01_create_control_schema.sql). The SQL Database Project under
`fabric/sqldb_ingestion_control.SQLDatabase/` is the corresponding tracked schema definition.

### SQL-enforced guardrails

The **SQL Database Project** under `fabric/sqldb_ingestion_control.SQLDatabase/` is the physical schema source of
truth. Key enforced constraints complement, rather than replace, pipeline validation:

| SQL object | Invariant |
| --- | --- |
| `control.connection_settings` | Supported connection types, nonblank reference, JSON object-root settings |
| `control.ingestion_config` | Nonblank core metadata; DATABASE requires `source_schema`, FILE requires `source_path`, `landing_path` and non-NULL `file_format`; INCREMENTAL requires `watermark_field`; optional JSON envelopes have object roots |
| `control.pipeline_watermarks` | One checkpoint per `ingestion_config_id`, no automatic reset, optimistic advancement through finalization |
| `audit.ingestion_log` | One terminal outcome per object Run ID, valid status/run type, nonnegative counts/duration, nonblank identity |
| `control.usp_validate_run_requests` | Reject malformed/NULL explicit request envelopes, invalid types and duplicates |
| `control.usp_finalize_ingestion_run` | Transactional audit and guarded watermark update; reject inconsistent repeated terminal outcomes |

SQL CHECK constraints permit some future FILE format labels, but **only DELIMITED_TEXT** has an implemented File
Router/reader. The non-destructive `scripts/control/01_create_control_schema.sql` bootstrap is **CREATE-IF-ABSENT**,
not a schema migration. `scripts/control/99_verify_control_plane.sql` verifies keys, enabled/trusted CHECK/FK
constraints, indexes, the view and two procedures; this is **not** a full column-by-column semantic schema diff. See
[SQL Run Order](../../scripts/RUN_ORDER.md) and [Environment Rebuild](../operations/environment-rebuild.md) for safe
installation, optional DEV seeds, and release checks.

## 2. How a configuration identifies one source object

A **source object** is one logical ingestion unit, not necessarily one physical file. For the implemented DATABASE
pattern, `source_schema` and `source_object` identify a SQL Server table. For FILE, `source_object` is a non-NULL
stable feed name (for example, `inventory_movement` ), while `source_path` and `source_options.file_name_pattern`
select eligible SFTP files. One FILE configuration can process multiple matching files in a run, with **one
configuration-level watermark** rather than separate per-file checkpoints. This is the framework's logical naming
contract, not a universal requirement imposed by Fabric.

Run this **read-only** query in `sqldb_ingestion_control` after the DEV sample metadata has been installed:

```sql
SELECT
    ingestion_config_id,
    source_system,
    source_schema,
    source_object,
    ingestion_pattern,
    load_strategy,
    watermark_field,
    source_conn_ref,
    target_conn_ref,
    target_schema,
    target_table,
    is_active
FROM control.ingestion_config
WHERE source_system IN ('ECOMMERCE', 'LOGISTICS_VENDOR')
ORDER BY source_system, ingestion_config_id;
```

The supplied DEV seed creates six `ECOMMERCE` database objects and two `LOGISTICS_VENDOR` file objects. The database
examples include `crm.customers`, `catalog.product_categories`, and `sales.order_items`. The file examples are
`inventory_snapshot` and `inventory_movement`.

Compare `catalog.product_categories` with `crm.customers`. The former is configured as `FULL` and has no watermark
field. The latter is `INCREMENTAL` with an `updated_at` watermark. Both use the same Orchestrator; the
object-specific behavior comes from the configuration and the selected adapter.

A configuration row also carries two logical connection references. The framework uses these references instead of
putting a physical Fabric Connection ID directly into every source object's pipeline parameters.

### Logical and physical connections are different

Inspect the logical references without returning the connection-settings JSON:

```sql
SELECT
    connection_ref,
    connection_type
FROM control.connection_settings
ORDER BY connection_ref;
```

For the standard demo, `SQL_SERVER_ECOMMERCE` is a SQL Server source, `SFTP_LOGISTICS_VENDOR` is an SFTP source, and
`LH_ECOMMERCE_BRONZE` is the Lakehouse target. Their physical connection and Lakehouse identifiers are stored in
`connection_settings` and resolved by `lkp_ingestion_config` in the Object Controller.

Fabric Pipeline activities use a separate set of runtime bindings, stored in `vl_ingestion_connections`, for
Control SQL, Invoke Pipeline, and Notebook execution. Those Library values are **not** the same as the per-source
`control.connection_settings` rows. For the actual binding contract, see
[Variable Library configuration](../operations/variable-library-environment-binding.md).

## 3. What changes between DATABASE and FILE?

`control.ingestion_config` is intentionally shared by both patterns. These fields explain the differences:

| Field | SQL Server example | SFTP example |
| --- | --- | --- |
| `ingestion_pattern` | `DATABASE` | `FILE` |
| `source_schema` | SQL schema such as `crm` | NULL |
| `source_path` | NULL | Remote SFTP folder |
| `file_format` | NULL | `DELIMITED_TEXT` |
| `source_options` | NULL in current DATABASE seed | JSON parsing and file-selection options |
| `landing_path` | NULL | Lakehouse Files-relative `landing/...` path |
| `load_strategy` | `FULL` or `INCREMENTAL` | `FULL` or `INCREMENTAL` |
| `watermark_field` | `updated_at` when incremental | `last_modified_time` when incremental |

The optional `copy_options` JSON is separate from `source_options`. The SQL Server demo uses it to choose Copy
partition behavior, such as `DYNAMIC_RANGE` for `sales.order_items`. File parsing details belong in
`source_options`.

To inspect the options of actual FILE configurations without changing them:

```sql
SELECT
    source_object,
    file_format,
    source_path,
    source_options,
    landing_path,
    load_strategy,
    watermark_field
FROM control.ingestion_config
WHERE source_system = 'LOGISTICS_VENDOR'
ORDER BY source_object;
```

The current reader implements CSV/TSV through `DELIMITED_TEXT`. Other format values appearing in SQL constraints are not evidence of corresponding working readers.

See [Database Copy Performance](../architecture/database-copy-performance.md) for the Copy option contract and [SFTP File Ingestion](sftp-file-ingestion.md) for the physical file path.

## 4. Which objects need watermark state?

FULL configurations do not maintain an incremental checkpoint. The two implemented INCREMENTAL patterns, DATABASE and FILE, share `control.pipeline_watermarks`.

Use the read-only query below to inspect which DEV configurations have stored state:

```sql
SELECT
    c.ingestion_config_id,
    c.source_system,
    c.source_object,
    c.load_strategy,
    c.watermark_field AS configured_watermark_field,
    w.watermark_field AS stored_watermark_field,
    w.last_watermark_value,
    w.last_successful_pipeline_run_id,
    w.watermark_updated_at
FROM control.ingestion_config AS c
LEFT JOIN control.pipeline_watermarks AS w
    ON w.ingestion_config_id = c.ingestion_config_id
WHERE c.source_system IN ('ECOMMERCE', 'LOGISTICS_VENDOR')
ORDER BY c.source_system, c.ingestion_config_id;
```

The LEFT JOIN is deliberate: a FULL row can legitimately have no checkpoint. An INCREMENTAL row with missing or
mismatched state is different. Its adapter checks for the expected configuration ID and watermark field and follows
a failure path if the state is unavailable.

For regular incremental execution, the stored value supplies LOW. The adapter determines HIGH according to its
source contract. For SQL Server, HIGH comes from the source query; for SFTP, the upper limit is the run start time.
A successful eligible REGULAR run may advance the checkpoint after the Bronze write succeeds and finalization
commits. BACKFILL never advances it. A no-new-data SKIPPED run does not advance it either.

The state comparison and transaction rules are explained in
[Generic Incremental Watermark](../architecture/generic-incremental-watermark.md) and implemented in
[02_create_control_procedures.sql](../../scripts/control/02_create_control_procedures.sql).

## 5. Where does the run history live?

A watermark answers "where should the next incremental run start?" It is not the full history of how the framework got there.

`audit.ingestion_log` keeps the terminal result for each object Pipeline Run ID. Inspect the latest records with:

```sql
SELECT TOP (20)
    ingestion_config_id,
    batch_id,
    pipeline_run_id,
    source_system,
    source_object,
    run_type,
    load_strategy,
    status,
    processing_lower_bound,
    processing_upper_bound,
    source_row_count,
    target_row_count,
    error_code,
    end_time
FROM audit.ingestion_log
ORDER BY ingestion_log_id DESC;
```

Two object runs may share a `batch_id` when one master execution dispatches multiple objects. They still have distinct object `pipeline_run_id` values.

The audit status records an object outcome such as `SUCCESS`, `FAILED`, or `SKIPPED`. This table does not
independently record every master-level failure before any object was dispatched, and it does not show in-progress
work. The [Monitoring Report](../operations/monitoring-report.md) explains the resulting visibility limits.

## 6. Follow the metadata into execution

The Object Controller's `lkp_ingestion_config` joins `control.ingestion_config` to `control.connection_settings` for
both source and target. It reads the load strategy and source options, validates the execution request and target
type, then selects the DATABASE or FILE Router.

You can inspect the exact Lookup and Switch definitions in:

- [Object Controller pipeline JSON](../../fabric/pl_ingest_object_controller.DataPipeline/pipeline-content.json)
- [DEV connection seed](../../scripts/control/03_seed_connection_settings.sql)
- [DEV ingestion configuration seed](../../scripts/control/04_seed_ingestion_metadata.sql)

The seed scripts are for creating or preparing a DEV example, **not** read-only verification scripts. In particular,
re-running the ingestion metadata seed may update existing demo configuration rows. Use the SELECT statements above
when you only want to study the current environment.

**Next:** [Pipeline Orchestration](pipeline-orchestration.md) shows how the master selects these configuration rows
and dispatches them. Then follow [SQL Server Database Ingestion](sql-server-database-ingestion.md) or
[SFTP File Ingestion](sftp-file-ingestion.md) into the source-specific adapters.

### Check the execution contract

Use the read-only configuration and watermark queries above to identify the actual object and its checkpoint. Then
inspect `lkp_ingestion_config` in the checked-in
[Object Controller definition](../../fabric/pl_ingest_object_controller.DataPipeline/pipeline-content.json) to see
how the metadata is passed to the router. The SQL results depend on the active DEV environment; do not assume the
example IDs or values match a fresh deployment.
