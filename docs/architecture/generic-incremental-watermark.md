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
FILE      last_modified_time  -> 2026-09-27T10:30:00.000
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
processing_lower_bound   = 2026-09-27T10:00:00.000
processing_upper_bound   = 2026-09-27T11:00:00.000
```

For DATABASE timestamp-watermark ingestion, boundary semantics are:

```text
REGULAR:
  upper > lower  -> process
  upper = lower  -> valid no-new-data window -> SUCCESS with zero rows
  upper < lower  -> invalid boundary -> FAILED

BACKFILL:
  upper > lower  -> process
  upper <= lower -> invalid boundary -> FAILED
```

For FILE Last Modified ingestion, both REGULAR and BACKFILL require `upper > lower`. A REGULAR no-new-file scan is still a forward time window and can finish `SUCCESS` with zero rows.

## Timestamp ownership and timezone contract

- Framework-created operational timestamp strings (`p_start_time`,
  `v_ingestion_timestamp`) represent UTC and carry a `Z` suffix. SQL audit
  `DATETIME2(3)` is stored as a timezone-less UTC value, by data type.
- Source-derived watermarks preserve their native type, precision and timezone
  interpretation. Do not blanket-convert watermarks to UTC or add `Z`.
  Azure SQL `DATETIME2(7)` source boundaries remain source-local and can
  retain seven fractional digits; watermark state stores them exactly.
- At connector boundaries, adapt representation only where required. For
  existing SFTP Last Modified filtering, the framework preserves its tested
  no-`Z` UTC watermark representation.

## Azure SQL timestamp-watermark precision

For Azure SQL incremental ingestion, the adapter preserves LOW/HIGH checkpoint values
from the control state and source Lookup without rounding or timestamp reformatting.
The shared `control.pipeline_watermarks.last_watermark_value` remains a STRING
(`NVARCHAR(1000)`) for exact optimistic-watermark comparison.

Both AUTO and TUNED Copy branches use `CONVERT(datetime2(7), '<boundary>', 126)`
in the **source SQL predicate**. SQL Server accepts timestamp strings with fewer
than seven fractional digits; `datetime2(7)` also preserves up to seven digits
from a higher-precision source. Do not use `formatDateTime(..., '...fff')`
on the boundary immediately before the SQL predicate: it would discard
fractional precision beyond milliseconds. This conversion is for source-side
filtering, not for storage of the checkpoint in the control SQL database.

Requested BACKFILL bounds must be SQL Server-parseable timestamps. ISO 8601 with
no timezone offset is recommended for the existing UTC, timezone-naive boundary
convention. Before onboarding a `datetime2(7)` source, verify that Fabric
Lookup, pipeline parameters and finalization preserve all seven digits
end-to-end. The SFTP connector's Last Modified filter semantics and operational
audit timestamp precision are separate and unchanged.

## FILE incremental choice

The first FILE incremental feed uses:

```text
watermark_field = last_modified_time
```

The SFTP adapter uses the connector's Last Modified window:

```text
modifiedDatetimeStart <= LastModified < modifiedDatetimeEnd
```

The existing FILE Last Modified watermark values remain UTC timestamp text
without a timezone suffix. This is a connector-specific, source-derived
checkpoint convention; framework-created operational timestamp strings now
carry `Z`. The REGULAR SFTP upper bound is formatted to no-`Z` UTC text before
it is used in filtering or persisted as a watermark.

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

A no-data FILE scan finishes as `SUCCESS` with zero rows and may still advance its Last Modified
window. Because it is a successful operational scan, the committed processing boundary advances normally.

## Run types and recovery

The framework run-type contract is intentionally small:

```text
REGULAR
= forward processing from the currently committed watermark

BACKFILL
= explicit historical LOW/HIGH processing that does not advance the operational watermark
```

Fabric Retry/Rerun is an execution-recovery mechanism, not a framework run type.
A failed REGULAR ingestion can be recovered by starting another top-level REGULAR
execution; the committed watermark remains the source of truth for the next
forward window.

BACKFILL may overlap a historical interval that was processed successfully before.
The framework does not delete or replace a previously successful Bronze batch when
that happens. Bronze remains append-oriented and each execution is distinguished by
its batch/run lineage. A future replace/reprocess mode should be added only if a
real downstream requirement needs replacement or deduplication semantics.
