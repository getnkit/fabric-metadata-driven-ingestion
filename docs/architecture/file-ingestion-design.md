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
- `copy_options`
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
= platform-owned Lakehouse Files-relative Landing Zone base path used before
  Bronze when the ingestion pattern requires a Landing step
  (example: landing/logistics_vendor/inventory_snapshot/; no Files/ prefix)
```

For the current DATABASE path, both fields are NULL because the source is already
identified by `source_schema` + `source_object` and the pipeline writes directly
to Bronze.

For FILE ingestion, both fields are first-class metadata. The FILE `landing_path` contract is strict: use `landing/...` (relative to the Lakehouse **Files** root), never `Files/landing/...`. The adapter concatenates this base path with `ingestion_date` and per-object execution segments without `replace()` or automatic path-prefix correction. Fabric Copy receives the Files-relative `folderPath`; Bronze and Landing-cleanup notebooks prepend the physical `/Files/` segment once. Historical audit paths and already-landed files are not relocated by this metadata change.

`file_format` is first-class FILE routing metadata because it changes how a raw Landing file is parsed into Bronze. The canonical values are `DELIMITED_TEXT`, `PARQUET`, and `JSON`.

`source_options` keeps parser/source-specific options that configure the selected parser but do not choose it. The current delimited-text feeds require `file_name_pattern`, `delimiter`, `has_header`, `encoding`, `quote`, and `escape`.

Current DATABASE configs use `file_format = NULL` and `source_options = NULL`. `copy_options` is a separate optional execution-tuning envelope; current FILE configs leave it NULL, while the Azure SQL adapter can use it for connector-native partitioned Copy behavior.

The current SQL Starter Kit seeds FILE `landing_path` directly as a Files-relative `landing/...` location. There is no legacy path-rewrite step in fresh installation. For an older populated environment with `Files/landing/...` metadata, review a targeted migration from Git history before execution; do not rewrite metadata or move historical Lakehouse files automatically.

## FILE flow

```text
Source connection + source_path
  -> Binary copy
  -> Landing + landing_path
  -> nb_load_file_landing_to_bronze
       -> format-specific reader
       -> common technical metadata
       -> Bronze Delta table
```

The source-to-Landing step is intentionally Binary so the delivered file is preserved byte-for-byte. Parsing starts only after the raw artifact reaches Landing.

The FILE Router now owns a single `if_supported_file_format` gate before `sw_file_route`, with the Personal `p_file_format` contract (`@equals(toUpper(pipeline().parameters.p_file_format), 'DELIMITED_TEXT')`). Unsupported formats are audited and failed once with `UNSUPPORTED_FILE_FORMAT` before invoking SFTP FULL or INCREMENTAL; the corresponding format gates and failure finalizers were removed from both SFTP adapters. The gate runs before incremental LOW/HIGH are resolved, so its failure audit has NULL processing bounds. In particular, an invalid format now takes precedence over state or boundary validation; supported formats continue through the existing adapter logic.

The reusable `nb_load_file_landing_to_bronze` notebook still owns format-specific reader dispatch and retains its own safety check. The current reader registry supports `DELIMITED_TEXT` only. `PARQUET` and `JSON` remain future readers rather than pipeline branches. Unsupported formats fail explicitly with `UNSUPPORTED_FILE_FORMAT` before raw Landing work starts.

Landing is retained for FILE ingestion because the delivered file is itself the raw ingestion artifact and can be reused for troubleshooting or reprocessing.

DATABASE ingestion remains direct-to-Bronze.

## Transfer consistency

The FILE pattern applies consistency controls per hop rather than forcing one
mechanism across every connector.

For the current SFTP-to-Landing Binary Copy, the adapter uses a framework-level
file-count gate after Copy succeeds:

```text
copy_sftp_to_landing
  -> filesRead == filesWritten
       -> true: continue
       -> false: finalize FAILED (LANDING_FILE_COUNT_MISMATCH) -> Fail
```

For INCREMENTAL SFTP, this gate runs before the no-new-data decision. Therefore
`0 filesRead / 0 filesWritten` is a valid consistent transfer and continues to
the no-new-data `SKIPPED` path with zero counts and no watermark advance, while a mismatched file count fails the run.

Landing-to-Bronze does not perform a second independent Bronze recount. The
notebook counts the parsed Landing DataFrame once, reuses that count as the
source/target audit metric after a successful atomic Delta append, and relies on
write failure plus the existing compensating-cleanup path for failed Bronze
writes. The audit count therefore documents rows processed by the successful
write; it is not an independent target reconciliation.

For future FILE connectors, use native Data Consistency Verification when the
actual Copy pair and execution mode support it. Otherwise use a
pattern-appropriate framework fallback such as the current SFTP file-count gate.

## Failure behavior

The current project does not implement Quarantine.

If a file cannot be found, opened, or parsed according to `source_options`, the
ingestion run fails and records the error in the normal ingestion audit path. A
file already copied to Landing remains there for inspection/reprocessing.

When SFTP landing Copy fails or its file counts mismatch, Landing cleanup
recursively deletes only the validated leaf folder ending in
`ingestion_config_id=<config_id>/batch_id=<batch_id>/pipeline_run_id=<object_controller_run_id>/`.
The cleanup Notebook requires these three matching IDs and the ingestion date
before deletion; it cannot delete another config's shared-batch Landing files.

When a failed path may already have appended rows to Bronze, the framework invokes
the reusable `nb_cleanup_bronze_batch_rows` notebook. Cleanup is scoped to both the
current `_batch_id` and object `_pipeline_run_id`, verifies that zero rows for
that object execution remain in Bronze, and only then allows the FAILED run to
be finalized. This makes a subsequent rerun
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

landing/logistics_vendor/inventory_snapshot/
= platform-owned raw Landing base path in control.ingestion_config (relative to Files/)

Runtime example:
Files/landing/logistics_vendor/inventory_snapshot/
  ingestion_date=YYYY-MM-DD/
    ingestion_config_id=<config_id>/
      batch_id=<batch_id>/
        pipeline_run_id=<object_controller_run_id>/
= date organization plus an isolated raw copy for one object execution.
The orchestrator may share batch_id across different configs; config_id and the
object controller's pipeline_run_id prevent same-root file collisions and
cross-execution Landing cleanup. Every audit landing_path records this physical
`Files/landing/...` execution folder, while Copy/Notebook/cleanup use the
corresponding relative `landing/...` path (the notebooks prepend `/Files/`).
```

The source inventory rows use the same SKU convention as the ECOMMERCE catalog
(`SKU000001`, `SKU000002`, and so on), which gives the demo a realistic
cross-source relationship without duplicating the Azure SQL source tables.

## Initial FILE fixture

Repository fixture:

```text
scripts/source/sftp/outbound/inventory/inventory_snapshot.csv
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
landing_path       = landing/logistics_vendor/inventory_snapshot/
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
  "encoding": "UTF-8",
  "quote": "\"",
  "escape": "\\"
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
landing_path       = landing/logistics_vendor/inventory_movement/
target_table       = fulfillment.inventory_movements
load_strategy      = INCREMENTAL
watermark_field    = last_modified_time
```

FILE incremental reuses `control.pipeline_watermarks`; there is no
FILE-specific state table.

The initial checkpoint is:

```text
1900-01-01T00:00:00.000
```

For each REGULAR run, the adapter uses:

```text
LOW  = current last_watermark_value
HIGH = ingestion run start time
```

SFTP Last Modified timestamps represent UTC by source contract. Both Copy
filter bounds use the documented UTC `yyyy-MM-ddTHH:mm:ss.fffZ` representation.
The REGULAR upper bound now preserves `p_start_time` (with `Z`) and a
successful run commits that upper bound as the next checkpoint. An existing
no-`Z` lower checkpoint is used unchanged for optimistic state comparison
and formatted as UTC with `Z` only for SFTP Copy. BACKFILL bounds must
represent UTC instants; convert any non-UTC offset to UTC before supplying
it rather than just appending `Z`.

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

After Landing succeeds, `nb_load_file_landing_to_bronze` recursively
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
      ingestion_config_id=<config_id>/
        batch_id=<batch_id>/
          pipeline_run_id=<object_controller_run_id>/
            2026/
              10/
                file.csv
```

For REGULAR execution, if the recursive Landing copy finds matching files and
the Bronze load succeeds, the pipeline watermark advances to `HIGH`. If no
matching files are found, the run is finalized as `SKIPPED` with zero rows and
**does not advance** the checkpoint; the next REGULAR scan retains the original
LOW. This intentionally allows a subsequent scan to discover late-arriving files
whose Last Modified falls within the previously empty window, at the cost of
rescanning that window. It does not guarantee detection of files delivered after
a later nonempty successful run has already advanced the watermark.

`run_type` and `load_strategy` are independent. The FILE config keeps its
configured FULL or INCREMENTAL strategy for every execution.

For an INCREMENTAL FILE config, BACKFILL reuses the bounded SFTP adapter and
applies the explicitly requested LOW/HIGH window to source-file Last Modified
time instead of the committed operational checkpoint. A successful INCREMENTAL BACKFILL does not advance the operational watermark.

For a FULL FILE config, BACKFILL rereads the same full currently available
source scope as FULL REGULAR execution. The distinction is execution intent and
lineage; each successful run still appends a new batch-specific Landing/Bronze
copy.

`p_start_time` is generated in UTC once at the Object Controller as
`yyyy-MM-ddTHH:mm:ss.fffZ`. It continues to supply the FILE REGULAR Last Modified
HIGH and the UTC `ingestion_date` in the approved batch-scoped Landing path.
The FILE Bronze Loader Notebook independently captures one UTC instant after
counting the parsed Landing rows and immediately before the Delta append:
`_ingestion_timestamp` uses that instant (serialized with millisecond precision
and `Z` before casting to Spark timestamp), and `_ingestion_date` uses the
UTC calendar date from the same instant. Existing file Bronze Delta schemas gain
`_ingestion_date` through the Loader's write-scoped `mergeSchema` option.
Landing `ingestion_date` and Bronze `_ingestion_date` can differ across UTC
midnight. The Bronze timestamp is the approximate write-start time, not the
Delta commit time. SQL `DATETIME2(3)` continues to represent UTC by convention.
FILE Watermark HIGH is persisted as the exact UTC-with-`Z` Object Run Start;
source-derived watermark bounds preserve their original precision and timezone
semantics. Do not append `Z` to a source-native value without a UTC contract.

The current SFTP incremental physical flow is therefore:

```text
pl_ingest_file_router
  -> if_supported_file_format (supported: DELIMITED_TEXT)
  -> sw_file_route (SFTP|INCREMENTAL)
  -> pl_ingest_sftp_incremental_adapter
      -> if_supported_watermark_field (last_modified_time)
      -> lkp_current_watermark
      -> if_state_found
      -> resolve LOW/HIGH for REGULAR or BACKFILL
      -> if_valid_processing_boundary
      -> copy_sftp_to_landing
       recursive = true
       wildcard file_name_pattern
       LOW <= LastModified < HIGH
       PreserveHierarchy
  -> if_landing_file_count_consistent
       filesRead == filesWritten
  -> if_no_new_data
       filesRead == 0
       -> true: sp_finalize_no_new_data_skipped (status=SKIPPED, advance_watermark=false)
       -> false: nb_load_file_landing_to_bronze
                    p_file_format
                    p_source_options
                 -> sp_finalize_success
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

The file config's normal REGULAR strategy is INCREMENTAL:

```text
REGULAR
LOW  = committed last_modified_time watermark
HIGH = ingestion run start time
advance operational watermark = yes
```

For the current INCREMENTAL FILE config, BACKFILL uses:

```text
BACKFILL + INCREMENTAL
LOW  = requested lower_bound
HIGH = requested upper_bound
advance operational watermark = no
```

For a FULL FILE config, BACKFILL uses no LOW/HIGH and rereads the configured
full current source scope. A future historical FULL-snapshot requirement would
need an explicit selector such as data_date, snapshot ID, source version, or a
historical file reference.

The current SFTP INCREMENTAL implementation applies LOW/HIGH to source-file Last
Modified time. Sources that preserve stale timestamps during late delivery or
require strict per-file receipt tracking still need a different policy such as
a manifest/receipt state model.


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
  -> nb_load_file_landing_to_bronze(p_file_format, p_source_options)
       -> DELIMITED_TEXT reader
       -> common Bronze write
```

The **FILE Router** performs the single framework-level supported-format guard before connector/strategy routing; SFTP FULL and INCREMENTAL do not repeat that check. It does not route to a different pipeline branch per file format. Reader selection lives inside the reusable notebook so future `PARQUET` or `JSON` support can reuse the same Landing, lineage, Bronze-write, row-count, and recovery behavior. When additional connector adapters support different subsets of formats, revisit the Router guard as an explicit route/adapter capability policy rather than assuming one global list fits every adapter.

## Generating new incremental SFTP fixtures for DEV tests

The checked-in `inventory_movement_*.csv` files are static reproducible fixtures.
To simulate new provider deliveries, use the optional [local Python movement
generator](../../scripts/source/sftp/README.md). It preserves the existing CSV
columns, writes fresh UTC-stamped filenames without overwriting old fixtures,
and can place files under `YYYY/MM/` to test recursive SFTP discovery. Upload
with the vendor/producer account to `/outbound/inventory/movements/`; the
generator does not automate SFTP upload or modify Fabric state.

For end-to-end incremental acceptance, observe **remote SFTP Last Modified**
time after upload, then verify REGULAR ingestion and watermark behavior.
The generated filename and row-level `occurred_at` are not used for FILE
watermark selection.
