# File Ingestion Design

## Status

Accepted direction for M76.

The personal project intentionally keeps FILE ingestion lean:

- one shared `control.ingestion_config`
- pattern-specific source options stored in `source_options`
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
- `ingestion_pattern`
- `target_folder`
- `target_conn_ref`
- `target_schema`
- `target_table`
- `load_strategy`
- `watermark_field`

`source_options` is an optional JSON object for pattern-specific source-reading
options that do not belong in the generic relational schema.

Example FILE value:

```json
{
  "file_format": "CSV",
  "source_folder": "incoming/customers",
  "file_name_pattern": "customers_*.csv",
  "delimiter": ",",
  "has_header": true,
  "encoding": "UTF-8"
}
```

Current DATABASE configs do not require source-specific options and therefore use
`NULL`.

## FILE flow

```text
Source file
  -> Landing (Lakehouse Files)
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
