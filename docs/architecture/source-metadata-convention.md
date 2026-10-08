# Source Metadata Convention

## Decision

`control.ingestion_config.source_object` is the stable identifier of a
source object/feed/resource **within its ingestion pattern**, used for
configuration identity, execution correlation, audit and watermark state.
The way the physical source is selected is pattern-specific. Do not
introduce a universal filename/endpoint fallback.

| Pattern | `source_object` | `source_path` | Physical selection |
| --- | --- | --- | --- |
| DATABASE (implemented) | Physical table/view name, e.g. `customers` | `NULL` | `source_schema` + `source_object` (`crm.customers`) |
| FILE (implemented via SFTP) | Stable feed ID, e.g. `inventory_movement` | Source folder, e.g. `/outbound/inventory/movements/` | Required `source_options.file_name_pattern`, e.g. `inventory_movement_*.csv` |
| API (design convention only) | Stable resource/operation ID | Not required | Future API adapter-owned endpoint, method and request metadata |

The DATABASE row retains the existing split between
`source_schema='crm'` and `source_object='customers'`; it does **not**
store `crm.customers` in the latter field. Current DATABASE pipelines,
source queries, source options and checkpoints are unchanged.

## FILE rules

1. `source_object` describes the feed, not a concrete file or wildcard.
   Its value and `ingestion_config_id` remain unchanged when a producer
   renames delivered files or changes their filename pattern.
2. `source_path` is the producer-owned source folder.
3. `source_options.file_name_pattern` is a required, non-blank filename or
   wildcard, independent of `source_object`. For selecting all files, a
   deliberate wildcard such as `*` is explicit metadata; missing/blank is not.
4. The Object Controller extracts the JSON filename pattern with SQL
   `JSON_VALUE` and passes `p_file_name_pattern` to the FILE Router/Adapters;
   there is no filename fallback to `source_object`. SFTP FULL and
   INCREMENTAL validate the parameter before Copy and fail fast with
   `INVALID_FILE_NAME_PATTERN` when missing or blank. Control SQL also
   rejects such FILE configurations via a CHECK constraint.
5. An existing FILE incremental watermark is keyed by
   `ingestion_config_id`, not the filename pattern. Changing just the
   physical pattern does not silently reset or advance the watermark.
   Operators must assess overlap/late-file effects separately when changing
   source file selection.

An **unmatched valid** wildcard remains a normal zero-file discovery for
SFTP INCREMENTAL; the framework cannot infer from an empty result whether the
producer missed an expected delivery. That requires separate monitoring,
not a fallback to an unrelated identifier.

## Migration / rollout

- Fresh databases: `scripts/control/01_create_control_schema.sql` includes
  `CK_ingestion_config_file_name_pattern` and the Fabric SQL Database
  project declares the same constraint.
- Existing databases: apply
  `scripts/control/migrations/008_require_file_name_pattern.sql` after the
  `file_format` migration. It rejects invalid FILE rows for explicit manual
  correction, and does not update configs or `control.pipeline_watermarks`.
- Sync updated SFTP pipelines before running. Runtime invalid-pattern
  finalization records FAILED / `INVALID_FILE_NAME_PATTERN`; no Copy or
  watermark advance is allowed.
- API is a future design extension only. Do not add API schema, endpoints,
  pipelines, or validation until there is an actual adapter implementation.

## Verification

Run `python -m unittest discover -s tests -v` for repository-level static
convention/structure checks. Also test a missing and blank pattern against
the live Fabric SQL Database and execute both SFTP adapters with invalid
metadata to verify audit finalization, no Landing write and no watermark
advance. Those integration checks require a real Fabric environment.
