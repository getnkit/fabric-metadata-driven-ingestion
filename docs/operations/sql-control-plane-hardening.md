# SQL Control Plane Hardening — Personal Baseline

## Intent

Task B closes the Personal framework's **SQL integrity and fresh-install**
gaps without importing TGH-specific Contracts, Config Versioning, DQ, or
logical-source watermark identity. The authoritative physical schema remains
`fabric/sqldb_ingestion_control.SQLDatabase/`.

There are four runtime tables:

- `control.connection_settings`
- `control.ingestion_config`
- `control.pipeline_watermarks`
- `audit.ingestion_log`

The existing `control.v_pipeline_watermarks` view, two ingestion Stored
Procedures, indexes and seed scripts remain part of the framework. Do not
rename columns or adjust watermark/audit transaction semantics in this task.

## Narrow integrity improvements

| Table | New or strengthened validation | Deliberately unchanged |
| --- | --- | --- |
| connection_settings | Nonblank reference (space/tab/CR/LF); `connection_settings` JSON **object** root | AZURE_SQL/SFTP/LAKEHOUSE type set, PK |
| ingestion_config | Required source/target identifiers nonblank; DATABASE source_schema nonblank; FILE source_path nonblank; FILE file_format explicitly NOT NULL; optional source_options/copy_options are JSON **objects** when supplied; INCREMENTAL watermark_field nonblank | 3 ingestion patterns, FULL/INCREMENTAL, FILE format enum allows future PARQUET/JSON, logical source UQ, connection FKs |
| pipeline_watermarks | Nonblank watermark_field and last_watermark_value | Config-ID primary key, optimistic checkpoint update |
| ingestion_log | Nonblank pipeline_run_id and pipeline_name; optional load_strategy limited to FULL/INCREMENTAL | UNIQUE pipeline_run_id, error/status/count/time constraints, history |
| request validator | A NULL JSON envelope is rejected (instead of SQL UNKNOWN bypass) | Valid run request shape/duplicate checks |

The FILE `landing_path` nonblank check introduced by migration `010`
continues unchanged. `FILE` can retain `PARQUET`/`JSON` metadata labels,
but runtime File Router rejects them until reader support is implemented.
No extra dynamic Pipeline validation activities were added.

**Important:** SQL CHECK accepts `UNKNOWN`. The updated FILE format rule
explicitly requires `file_format IS NOT NULL`; the earlier expression could
accept FILE + NULL despite an apparent enum restriction.

## Permanent fresh installation

The lean canonical package stays at these paths (no bulk historical rename):

1. `scripts/control/01_create_control_schema.sql`
   - Creates `control`/`audit` schemas if absent.
   - Creates four tables if absent, then the three audit access indexes if absent.
   - `CREATE OR ALTER VIEW control.v_pipeline_watermarks`.
   - **No DROP TABLE/VIEW and no automatic data reset.**
2. `scripts/control/02_create_control_procedures.sql`
   - CREATE OR ALTER both ingestion procedures, without changing finalizer
     audit/watermark atomicity, idempotence, status or error semantics.
3. `scripts/control/03_seed_connection_settings.sql`
4. `scripts/control/04_seed_ingestion_metadata.sql`
5. `scripts/control/99_verify_control_plane.sql`
   - Read-only check for required tables, view, procedures, `landing_path`
     column, 21 CHECK constraints (enabled/trusted), 6 PK/UQ constraints,
     3 trusted FKs and 3 audit indexes.

**The SQL Database Project is the source of truth.** CREATE-IF-ABSENT
bootstrap does not upgrade a populated schema. Verification is therefore
required, even if the bootstrap printed success.

## Existing DEV upgrade (no state reset)

1. Pause writes and capture a rollback-safe database snapshot/export of
   `control.*` and `audit.*`, especially `pipeline_watermarks`.
2. Check `scripts/control/migrations/001` through `010` for structural
   steps that your DEV installation still needs. In particular ensure
   historical `audit.ingestion_log.target_path` became `landing_path`,
   and FILE Landing path migration `009` / constraint `010` were applied
   when relevant. Apply earlier migrations **before** `011`.
3. Review `scripts/control/migrations/011_harden_control_plane_constraints.sql`
   before executing it. The migration preflights the current rows and performs
   constraint changes inside one transaction with `WITH CHECK`.
   - If a row fails, the migration throws and rolls back without updating,
     deleting, or resetting any config/checkpoint/audit rows.
   - Repair offending metadata/history deliberately. Do not set a different
     watermark field/value, clear audit data, or reset state to satisfy a CHECK.
   - Rerunning after cleanup reasserts the 12 upgraded constraints idempotently.
4. Deploy SQL Database Project DDL in a reviewed deployment (where used);
   run `scripts/control/02_create_control_procedures.sql` to update the NULL
   run request safeguard; execute `scripts/control/99_verify_control_plane.sql`.
   Do not mix an automated SQL Project deployment with concurrent manual DDL.
5. Validate representative SQL failures and happy-path ingestion in Fabric DEV:
   FILE FULL/INCREMENTAL, Azure SQL FULL/INCREMENTAL, no-new-data SKIPPED,
   BACKFILL without operational watermark advancement, audit idempotence,
   failed-copy cleanup and optimistic concurrency conflict. Validate after
   Task A Variable Library connections are configured.

Migration `011` only manages this task's constraints. It does not
change foreign/unique keys or guarantee unrelated historical structural
changes are already deployed. `99` detects missing/disabled core objects,
not every possible semantic difference in column definitions. A schema
diff against the SQL Database Project must complement `99` before PROD.

## Historical migration files

Keep `scripts/control/migrations/001`–`011` as **upgrade history**.
Do not run all of them on a fresh database, and do not delete them merely to
make the fresh-install folder look shorter. They record safe changes for
older DEV installations. The standard install surface is the five scripts
listed above; they are not ad hoc patches.

## Release status

This Git implementation undergoes static checks and definition comparison.
It is **not** a successful SQL Database deployment or proof of Microsoft
Fabric SQL runtime compatibility. Perform DEV migration and negative-data
acceptance before production promotion.
