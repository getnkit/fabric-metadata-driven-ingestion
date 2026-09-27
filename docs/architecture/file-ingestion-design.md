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
= source location or identifier used to locate the delivered source data

landing_path
= platform-owned Landing Zone path used before Bronze when the ingestion pattern
  requires a Landing step
```

For the current DATABASE path, both fields are NULL because the source is already
identified by `source_schema` + `source_object` and the pipeline writes directly
to Bronze.

For FILE ingestion, both fields are first-class metadata:

```text
source_path  = incoming/customers/
landing_path = Files/landing/customers/
```

`source_options` is an optional JSON object for pattern-specific source-reading
options that do not belong in the generic relational schema.

Example FILE value:

```json
{
  "file_format": "CSV",
  "file_name_pattern": "customers_*.csv",
  "delimiter": ",",
  "has_header": true,
  "encoding": "UTF-8"
}
```

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

Additional file formats, SFTP, API ingestion, schema-contract governance, and
incremental file state may be added later without changing the top-level
`ingestion_pattern` routing model.


## First physical adapter

The first physical FILE source adapter is SFTP.

The demo models an external producer/vendor that publishes files to its outbound
delivery area:

```text
External producer/vendor
  -> SFTP /outbound/customers/
  -> Fabric Data Factory
  -> OneLake Landing
  -> Bronze Delta table
```

The SFTP directory is producer-owned delivery space; it is not the platform
Landing Zone. The platform-owned copy begins at `landing_path`.

Initial M76 fixture:

```text
source_path       = /outbound/customers/
file_name_pattern = customers_*.csv
```

The repository fixture is stored under
`sample-data/sftp/outbound/customers/` so the demo can be reproduced without
depending on the operational SFTP server contents.
