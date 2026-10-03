# File Ingestion Design

## Status

FILE/FULL is implemented and acceptance-tested. FILE/INCREMENTAL extends the same design by reusing the framework-wide pipeline watermark state.

The personal project intentionally keeps FILE ingestion lean:

- one shared `control.ingestion_config`
- first-class `source_path`, `landing_path`, and `file_format`
- pattern-specific parser/source-reading options stored in `source_options`
- no `control.file_ingestion_config`
- no Data Contract subsystem in the current scope
- no Quarantine / Reject Area

## Metadata model

`control.ingestion_config` remains the single ingestion configuration table.

The generic columns continue to own routing and execution metadata:

- `source_system`
- `source_conn_ref`
- `source_schema`
- `source_object`
- `source_path`
- `ingestion_pattern`
- `file_format`
- `source_options`
- `landing_path`
- `target_conn_ref`
- `target_schema`
- `target_table`
- `load_strategy`
- `watermark_field`

Path semantics:

```text
source_path
= source-owned location used to locate delivered source data

landing_path
= platform-owned Landing Zone path used before Bronze when the ingestion pattern
  requires a Landing step
```

For the current DATABASE path, both fields are NULL because the source is already
identified by `source_schema` + `source_object` and the pipeline writes directly
to Bronze.

For FILE ingestion, both fields are first-class metadata.

`file_format` is first-class FILE routing metadata because it changes how a raw Landing file is parsed into Bronze. The canonical values are `DELIMITED_TEXT`, `PARQUET`, and `JSON`.

`source_options` keeps parser/source-specific options that configure the selected parser but do not choose it. The current delimited-text feeds use `file_name_pattern`, `delimiter`, `has_header`, and `encoding`.

Current DATABASE configs use `file_format = NULL` and `source_options = NULL`.

## FILE flow

```text
Source connection + source_path
  -> Binary copy
  -> Landing + landing_path
  -> nb_load_landing_to_bronze
       -> format-specific reader
       -> common technical metadata
       -> Bronze Delta table
```

The source-to-Landing step is intentionally Binary so the delivered file is preserved byte-for-byte. Parsing starts only after the raw artifact reaches Landing.

The reusable `nb_load_landing_to_bronze` notebook owns format-specific reader dispatch. The current reader registry supports `DELIMITED_TEXT` only. `PARQUET` and `JSON` remain future readers rather than pipeline branches. Unsupported formats fail explicitly with `UNSUPPORTED_FILE_FORMAT` before raw Landing work starts.

Landing is retained for FILE ingestion because the delivered file is itself the raw ingestion artifact and can be reused for troubleshooting or reprocessing.

DATABASE ingestion remains direct-to-Bronze.

## Failure behavior

The current project does not implement Quarantine.

If a file cannot be found, opened, or parsed according to `source_options`, the
ingestion run fails and records the error in the normal ingestion audit path. A
file already copied to Landing remains there for inspection/reprocessing.

When a failed path may already have appended rows to Bronze, the framework invokes
the reusable `nb_cleanup_bronze_batch_rows` notebook. Cleanup is scoped to the
current `_batch_id`, verifies that the batch has zero remaining Bronze rows, and
only then allows the FAILED run to be finalized. This makes a subsequent rerun
safe without turning Bronze into a MERGE/deduplication layer.

The framework intentionally does not auto-clean after an ambiguous
`sp_finalize_success` failure because the control transaction may already have
committed.

Business data-quality and a governed Data Contract model are intentionally outside
the current M76 scope.

## Scope of M76

The first implementation proves one metadata-driven CSV path:

```text
FILE + FULL + CSV
  -> Landing
  -> Bronze
```

The first FILE/FULL fixture is deliberately modeled as a complete inventory
snapshot so FULL semantics are natural: the delivered file represents the full
inventory state for the snapshot time.

The producer publishes a stable current-snapshot filename (`inventory_snapshot.csv`).
Using a stable name avoids a FULL run accidentally replaying every historical
date-stamped snapshot in the source folder. Each run preserves the raw file in
a batch-specific Landing subfolder before Bronze ingestion.

Incremental FILE ingestion reuses the framework-wide pipeline watermark state
rather than introducing a FILE-specific state table. The first incremental feed
is `inventory_movement` and uses the source file Last Modified timestamp as
its checkpoint during normal REGULAR execution.

## First physical adapter and source story

The first physical FILE adapter is SFTP.

The demo models an external logistics vendor. The provider's
Warehouse Management System (WMS) publishes a complete inventory snapshot to its
SFTP outbound area. Fabric consumes that file into the platform-owned OneLake
Landing Zone before writing Bronze.

```text
External logistics vendor
  -> SFTP /outbound/inventory/
  -> Fabric Data Factory
  -> Files/landing/logistics_vendor/inventory_snapshot/
  -> Bronze fulfillment.inventory_snapshots
```

This separates ownership cleanly:

```text
/outbound/inventory/
= source/provider-owned delivery path

Files/landing/logistics_vendor/inventory_snapshot/
= platform-owned raw Landing base path

Runtime example:
Files/landing/logistics_vendor/inventory_snapshot/
  ingestion_date=YYYY-MM-DD/
    batch_id=<batch_id>/
= human-browsable date organization plus immutable raw copy for one ingestion run
```

The source inventory rows use the same SKU convention as the ECOMMERCE catalog
(`SKU000001`, `SKU000002`, and so on), which gives the demo a realistic
cross-source relationship without duplicating the Azure SQL source tables.

## Initial FILE fixture

Repository fixture:

```text
sample-data/sftp/outbound/inventory/inventory_snapshot.csv
```

Source SFTP path and file pattern:

```text
source_path       = /outbound/inventory/
file_name_pattern = inventory_snapshot.csv
```

Fixture columns:

```text
warehouse_code
sku
on_hand_qty
reserved_qty
available_qty
inventory_status
snapshot_at
```

## Initial FILE configuration

```text
source_system      = LOGISTICS_VENDOR
source_conn_ref    = SFTP_LOGISTICS_VENDOR
source_schema      = NULL
source_object      = inventory_snapshot
source_path        = /outbound/inventory/
ingestion_pattern  = FILE
file_format        = DELIMITED_TEXT
landing_path       = Files/landing/logistics_vendor/inventory_snapshot/
target_conn_ref    = LH_ECOMMERCE_BRONZE
target_schema      = fulfillment
target_table       = inventory_snapshots
load_strategy      = FULL
watermark_field    = NULL
```

`source_options`:

```json
{
  "file_name_pattern": "inventory_snapshot.csv",
  "delimiter": ",",
  "has_header": true,
  "encoding": "UTF-8"
}
```

The FILE/FULL config is active because its route has passed acceptance testing.

## SFTP account roles

The demo uses two SFTP identities to preserve the producer/consumer boundary:

```text
vendor_sftp_user
= producer-side account used to simulate the external logistics vendor delivering files

fabric_sftp_user
= read-only consumer account used by Fabric Data Factory
```

The account name `vendor_sftp_user` is therefore intentional in this scenario.

## FILE incremental feed

The first incremental FILE feed is:

```text
source_object      = inventory_movement
source_path        = /outbound/inventory/movements/
file_format        = DELIMITED_TEXT
file_name_pattern  = inventory_movement_*.csv
landing_path       = Files/landing/logistics_vendor/inventory_movement/
target_table       = fulfillment.inventory_movements
load_strategy      = INCREMENTAL
watermark_field    = last_modified_time
```

FILE incremental reuses `control.pipeline_watermarks`; there is no
FILE-specific state table.

The initial checkpoint is:

```text
1900-01-01T00:00:00.000Z
```

For each REGULAR run, the adapter uses:

```text
LOW  = current last_watermark_value
HIGH = ingestion run start time
```

and selects source files whose Last Modified value is in:

```text
LOW <= LastModified < HIGH
```

SFTP incremental discovery supports arbitrary nested subfolders beneath
`source_path` without implementing folder traversal in pipeline control flow.

The SFTP Copy activity performs one recursive Binary copy from the configured
source root to the batch-specific Landing folder. It applies the configured
`file_name_pattern` together with the LOW/HIGH Last Modified window and uses
`PreserveHierarchy`, so the connector itself handles arbitrary folder depth.

After Landing succeeds, `nb_load_landing_to_bronze` recursively
reads only that batch's Landing folder, parses the delimited files, adds the
technical lineage columns, and appends the result to the Bronze Delta table.

This keeps responsibilities narrow:

```text
SFTP connector
  = recursive discovery + Last Modified filtering + raw Binary landing

Notebook
  = recursive Landing parsing + technical metadata + Bronze Delta append
```

Every matching file is copied to the batch-specific Landing folder and then
appended to Bronze. The file's relative source-folder hierarchy is preserved
under the batch root, for example:

```text
source:
  /outbound/inventory/movements/2026/10/file.csv

landing:
  Files/landing/logistics_vendor/inventory_movement/
    ingestion_date=YYYY-MM-DD/
      batch_id=<batch_id>/
        2026/
          10/
            file.csv
```

If the recursive Landing copy finds matching files and the Bronze load succeeds,
the pipeline watermark advances to `HIGH`. If the recursive copy finds no
matching files, the run is recorded as `SKIPPED` and can still advance the Last
Modified checkpoint to `HIGH`; this avoids repeatedly rescanning the same empty
time window.

The current SFTP incremental physical flow is therefore:

```text
pl_ingest_sftp_incremental
  -> if_supported_file_format
  -> copy_sftp_to_landing
       recursive = true
       wildcard file_name_pattern
       LOW <= LastModified < HIGH
       PreserveHierarchy
  -> if_files_found
       -> nb_load_landing_to_bronze
            p_file_format
            p_source_options
       -> sp_finalize_success
       -> no files
            -> sp_finalize_skipped
```

The previous explicit folder-queue / Until / scanner-pipeline design was removed
because it duplicated recursive traversal already provided by the SFTP Copy
connector.

The source filename remains evidence and lineage metadata in Bronze
(`_source_file_name`, `_source_file_path`) but is not used as the checkpoint.

Fixture names therefore do not need sortable sequence suffixes. The current
fixtures use delivery timestamps only to keep the example files unique:

```text
inventory_movement_20260927T081500Z.csv
inventory_movement_20260927T131500Z.csv
2026/10/inventory_movement_20261002T150000Z.csv
```

This strategy assumes the SFTP server exposes a reliable UTC Last Modified value
that reflects delivery/update time. A source that preserves stale timestamps
during late delivery or requires strict per-file receipt tracking would need a
different policy such as a manifest/receipt state model.

FILE + INCREMENTAL initially supports `REGULAR` runs only. Replay semantics
will be designed separately rather than reusing relational RERUN/BACKFILL
datetime parameters implicitly.


## Format-routing boundary

`source_connection_type` and `file_format` answer different questions:

```text
source_connection_type
= how the raw file reaches Landing

file_format
= how the Landing artifact is parsed into Bronze
```

For the current SFTP adapter:

```text
SFTP
  -> Binary copy to Landing
  -> nb_load_landing_to_bronze(p_file_format, p_source_options)
       -> DELIMITED_TEXT reader
       -> common Bronze write
```

The pipeline performs only a supported-format guard; it does not route to a different pipeline branch per file format. Reader selection lives inside the reusable notebook so future `PARQUET` or `JSON` support can reuse the same Landing, lineage, Bronze-write, row-count, and recovery behavior.
