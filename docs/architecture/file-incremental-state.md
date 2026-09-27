# FILE Incremental State

## Decision

FILE incremental ingestion uses a processed-file manifest instead of a
relational watermark.

```text
control.pipeline_watermarks
= DATABASE incremental current position

control.file_ingestion_state
= FILE incremental successfully processed file identities
```

The first feed is `LOGISTICS_VENDOR.inventory_movement`.

## File identity contract

Within one ingestion config:

- `source_file_name` is the file identity.
- File names must be unique.
- A delivered file is immutable.
- Replacing content under an already processed file name is not treated as a
  new delivery.

This contract allows late-arriving files to be processed even when their names
or business timestamps are older than files already processed.

## Runtime flow

```text
SFTP folder
  -> Get Metadata childItems
  -> file_name_pattern filter
  -> for each candidate file
       -> check control.file_ingestion_state
       -> if unseen:
            SFTP -> Landing
            Landing -> Bronze
            mark file processed
  -> SUCCESS when >= 1 unseen file was processed
  -> SKIPPED when every matching file was already processed
```

The ForEach is sequential in the first implementation. This keeps state
transitions deterministic and avoids concurrent attempts to process the same
file while the framework is still intentionally small.

## Delivery guarantee

The processed-file state row is inserted only after the Bronze copy succeeds.
The state write is idempotent and retried.

Bronze and Fabric SQL Database do not share a distributed transaction, so a
failure after Bronze succeeds but before the state row is committed can cause a
file to be retried. The Bronze technical columns `_source_file_name`,
`_source_file_path`, `_batch_id`, and `_pipeline_run_id` make that case
traceable. The framework therefore does not claim strict exactly-once delivery.

## Run types

The initial FILE incremental route supports `REGULAR` only.

`RERUN` and `BACKFILL` are intentionally not mapped to relational LOW/HIGH
parameters. Future replay should select explicit file identities or file-state
criteria.
