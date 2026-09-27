# Generic Incremental Watermark

## Decision

All incremental ingestion patterns share one persistent checkpoint table:

```text
control.pipeline_watermarks
```

The table stores the last committed checkpoint for one `ingestion_config_id`:

```text
watermark_field
last_watermark_value
last_successful_batch_id
last_successful_pipeline_run_id
watermark_updated_at
```

`last_watermark_value` is stored as STRING so the state model can represent
different checkpoint mechanisms without creating pattern-specific state tables.

Examples:

```text
DATABASE  updated_at          -> 2026-09-27T10:30:00.000
FILE      last_modified_time  -> 2026-09-27T10:30:00.000Z
API       sync_token          -> opaque provider token
API       updated_at          -> 2026-09-27T10:30:00.000Z
STREAM    source_sequence     -> 123456789
CDF       commit_version      -> 981
```

The physical adapter owns interpretation of the STRING checkpoint.

## Generic processing boundaries

The audit/finalization interface uses the same two generic boundary fields for
all ingestion patterns:

```text
processing_lower_bound
processing_upper_bound
```

Both are STRING.

No parallel `watermark_lower_value` / `watermark_upper_value` parameters are
used. There is also no `processing_boundary_type` in the current personal
project; `ingestion_pattern` plus `watermark_field` already provides enough
context for the implemented adapters.

Examples:

```text
DATABASE
watermark_field          = updated_at
processing_lower_bound   = 2026-09-27T10:00:00.000
processing_upper_bound   = 2026-09-27T11:00:00.000

FILE
watermark_field          = last_modified_time
processing_lower_bound   = 2026-09-27T10:00:00.000Z
processing_upper_bound   = 2026-09-27T11:00:00.000Z
```

## FILE incremental choice

The first FILE incremental feed uses:

```text
watermark_field = last_modified_time
```

The SFTP adapter uses the connector's Last Modified window:

```text
modifiedDatetimeStart <= LastModified < modifiedDatetimeEnd
```

Operationally, the lower boundary is the previously committed watermark and the
upper boundary is captured at the start of the current ingestion run. After a
successful scan, the watermark advances to that upper boundary.

The source filename remains a file identity/evidence field, not the incremental
checkpoint.

The fixture names therefore only need to be unique and match the configured
pattern. They do not need a sortable `_001`, `_002` sequence.

## Delivery assumption

Last Modified is the default FILE checkpoint for this implementation because it
matches the native file filtering model of Microsoft Data Factory connectors.

The producer/source system must expose a reliable UTC Last Modified value that
changes when a file is newly delivered or replaced. If a future source preserves
old timestamps during late delivery, or requires strict per-file receipt
tracking, a manifest/receipt strategy is more appropriate than one scalar
watermark.

## Finalization

`control.usp_finalize_ingestion_run` compares the stored
`last_watermark_value` with `processing_lower_bound` before advancing it to
`processing_upper_bound`.

This optimistic comparison keeps the watermark state update and terminal audit
insert atomic inside the control SQL database.

A no-data FILE scan can finish as `SKIPPED` and still advance its Last Modified
window. In that case the previous last-successful-data batch/run references are
preserved.
