# Generic Incremental Watermark

## Decision

All ingestion patterns share one persistent checkpoint table:

```text
control.pipeline_watermarks
```

The table stores the last successfully committed checkpoint for an
`ingestion_config_id`.

```text
watermark_field
last_watermark_value
last_successful_batch_id
last_successful_pipeline_run_id
watermark_updated_at
```

`last_watermark_value` is stored as STRING so the state model can represent
different incremental mechanisms without creating pattern-specific state tables.

Examples:

```text
DATABASE  updated_at          -> 2026-09-27T10:30:00.000
FILE      source_file_name    -> inventory_movement_20260927_002.csv
API       sync_token          -> opaque provider token
API       updated_at          -> 2026-09-27T10:30:00.000Z
STREAM    source_sequence     -> 123456789
CDF       commit_version      -> 981
```

The physical adapter is responsible for interpreting the checkpoint value.

## FILE incremental choice

The first FILE incremental feed uses:

```text
watermark_field = source_file_name
```

The delivered filenames are fixed-width and lexicographically sortable:

```text
inventory_movement_20260927_001.csv
inventory_movement_20260927_002.csv
inventory_movement_20260928_001.csv
```

The date + sequence encoded in the filename provides the ordering contract.
The implementation deliberately does not use SFTP file modification time as the
checkpoint because modification time can change when a file is copied, touched,
or re-uploaded and is therefore less stable than an explicit producer sequence.

Microsoft Fabric pipeline expressions support string comparison with
`greater()`, so fixed-width sortable filenames can be compared directly.

## Delivery contract

The first FILE incremental implementation requires:

- file names are unique within the feed
- files are immutable after delivery
- filename ordering is monotonic
- the producer does not deliver a lower-sequence file after a higher checkpoint
  has been committed

If a future source cannot guarantee monotonic delivery, a receipt/manifest model
or gap-aware sequence policy is more appropriate than a single scalar watermark.

## Finalization

`control.usp_finalize_ingestion_run` supports both:

- relational DATETIME LOW/HIGH boundaries
- generic STRING watermark lower/upper values

The optimistic concurrency check remains the same: the stored checkpoint must
still equal the value read at the start of the run before it is advanced.

This keeps watermark state and the terminal audit insert in one SQL transaction.
