# File Ingestion Design

## Goal

Implement a real FILE ingestion path without forcing file-specific metadata into
the generic ingestion table.

The first implementation is self-contained and uses Lakehouse Files as the source
drop zone. SFTP or ADLS can be added later as physical source adapters without
changing the FILE routing contract.

## Logical flow

```text
pl_master_ingestion
  -> pl_ingest_object
      -> FILE|LAKEHOUSE|FULL
          -> pl_ingest_file_full
              -> source connector adapter
              -> copy original file to Landing
              -> structural contract validation
                  -> valid   -> append to Bronze Delta table
                  -> invalid -> quarantine original landed file
              -> audit/finalization
```

For file ingestion, Landing is retained because the original delivered file is an
operational checkpoint and evidence artifact. Database ingestion continues to
write directly to Bronze.

## Generic metadata

`control.ingestion_config` remains the common object-level configuration.

For FILE configs:

- `ingestion_pattern = FILE`
- `source_schema` may be NULL
- `source_object` is the logical data object, not the physical filename
- `target_folder` is the Lakehouse Files Landing folder
- `target_schema` / `target_table` identify the Bronze Delta table
- the first implementation uses `load_strategy = FULL`
- `watermark_field` is NULL

## File-specific metadata

`control.file_ingestion_config` stores fields that apply only to FILE ingestion:

- source folder
- filename/pattern
- file format
- CSV parsing options when applicable
- expected structural schema
- quarantine folder

This keeps DATABASE and future API configs free from irrelevant file columns.

## Validation boundary

Pre-Bronze validation is structural only. It verifies that the delivered file can
be interpreted according to the configured file contract, for example:

- supported file format
- parseability
- required columns / expected structure
- CSV header/delimiter expectations when applicable

Business data-quality rules remain a Bronze-to-Silver responsibility.

## Failure behavior

A structurally invalid file is not loaded into Bronze. The landed file is moved or
copied to the configured quarantine location and the ingestion run is finalized
as failed with a diagnostic error.

A successful file load appends to Bronze and records the landed path in
`audit.ingestion_log.target_path`.

## Extensibility

The FILE pipeline owns file-processing semantics; physical source adapters own
only source-access behavior.

Future examples:

```text
pl_ingest_file_full
  -> LAKEHOUSE_FILES
  -> SFTP
  -> ADLS_GEN2
```

Adding an SFTP adapter must not change the Landing -> validation -> Bronze
contract.
