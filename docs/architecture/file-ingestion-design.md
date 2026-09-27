# File Ingestion Design

## Status

FILE/FULL is implemented and acceptance-tested. FILE/INCREMENTAL extends the same design by reusing the framework-wide pipeline watermark state.

The personal project intentionally keeps FILE ingestion lean:

- one shared `control.ingestion_config`
- first-class `source_path` and `landing_path`
- pattern-specific source-reading options stored in `source_options`
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

`source_options` is an optional JSON object for pattern-specific source-reading
options that do not belong in the generic relational schema.

Current DATABASE configs do not require source-specific options and therefore use
`source_options = NULL`.

## FILE flow

```text
Source connection + source_path
  -> Landing + landing_path
  -> FILE ingestion pipeline
  -> Bronze Delta table
```

Landing is retained for FILE ingestion because the delivered file is itself the
raw ingestion artifact and can be reused for troubleshooting or reprocessing.

DATABASE ingestion remains direct-to-Bronze.

## Failure behavior

The current project does not implement Quarantine.

If a file cannot be found, opened, or parsed according to `source_options`, the
ingestion run fails and records the error in the normal ingestion audit path. A
file already copied to Landing remains there for inspection/reprocessing.

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
  "file_format": "CSV",
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

and asks the SFTP connector to return child files in the Last Modified window:

```text
LOW <= LastModified < HIGH
```

The configured `file_name_pattern` is then applied to the returned child file
names. Every matching file is copied to the batch-specific Landing folder and
then appended to Bronze. If the scan completes successfully, the pipeline
watermark advances to `HIGH`.

A scan with no matching files is recorded as `SKIPPED` but can still advance
the Last Modified checkpoint to `HIGH`; this avoids repeatedly rescanning the
same empty time window.

The source filename remains evidence and lineage metadata in Bronze
(`_source_file_name`, `_source_file_path`) but is not used as the checkpoint.

Fixture names therefore do not need sortable sequence suffixes. The current
fixtures use delivery timestamps only to keep the example files unique:

```text
inventory_movement_20260927T081500Z.csv
inventory_movement_20260927T131500Z.csv
```

This strategy assumes the SFTP server exposes a reliable UTC Last Modified value
that reflects delivery/update time. A source that preserves stale timestamps
during late delivery or requires strict per-file receipt tracking would need a
different policy such as a manifest/receipt state model.

FILE + INCREMENTAL initially supports `REGULAR` runs only. Replay semantics
will be designed separately rather than reusing relational RERUN/BACKFILL
datetime parameters implicitly.
