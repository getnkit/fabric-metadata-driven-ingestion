# File Ingestion Design

## Status

Accepted direction for M76.

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

Incremental FILE ingestion remains planned for a later milestone and will add
file-processing state semantics rather than reusing relational watermarks.

## First physical adapter and source story

The first physical FILE adapter is SFTP.

The demo models an external third-party logistics (3PL) provider. The provider's
Warehouse Management System (WMS) publishes a complete inventory snapshot to its
SFTP outbound area. Fabric consumes that file into the platform-owned OneLake
Landing Zone before writing Bronze.

```text
External 3PL WMS
  -> SFTP /outbound/inventory/
  -> Fabric Data Factory
  -> Files/landing/3pl_wms/inventory_snapshot/
  -> Bronze fulfillment.inventory_snapshots
```

This separates ownership cleanly:

```text
/outbound/inventory/
= source/provider-owned delivery path

Files/landing/3pl_wms/inventory_snapshot/
= platform-owned raw Landing path
```

The source inventory rows use the same SKU convention as the ECOMMERCE catalog
(`SKU000001`, `SKU000002`, and so on), which gives the demo a realistic
cross-source relationship without duplicating the Azure SQL source tables.

## Initial FILE fixture

Repository fixture:

```text
sample-data/sftp/outbound/inventory/inventory_snapshot_20260927_001.csv
```

Source SFTP path and file pattern:

```text
source_path       = /outbound/inventory/
file_name_pattern = inventory_snapshot_*.csv
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
source_system      = 3PL_WMS
source_conn_ref    = SFTP_3PL_WMS
source_schema      = NULL
source_object      = inventory_snapshot
source_path        = /outbound/inventory/
ingestion_pattern  = FILE
landing_path       = Files/landing/3pl_wms/inventory_snapshot/
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
  "file_name_pattern": "inventory_snapshot_*.csv",
  "delimiter": ",",
  "has_header": true,
  "encoding": "UTF-8"
}
```

The config is seeded with `is_active = 0` until the FILE route is implemented,
so the existing all-active master run remains green during M76 development.

## SFTP account roles

The demo uses two SFTP identities to preserve the producer/consumer boundary:

```text
vendor_sftp_user
= producer-side account used to simulate the external 3PL WMS delivering files

fabric_sftp_user
= read-only consumer account used by Fabric Data Factory
```

The account name `vendor_sftp_user` is therefore intentional in this scenario.
