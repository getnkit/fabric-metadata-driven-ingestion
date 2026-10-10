# SFTP Inventory Movement Test Generator

The `generate_inventory_movement.py` script simulates a logistics vendor publishing **new** inventory-movement CSV files. It is a **producer-side test utility**, not a Fabric pipeline or scheduler. It requires **Python 3.9+**, using only the standard library.

It preserves the existing fixture's six-column contract:

```text
movement_id,warehouse_code,sku,movement_type,quantity_change,occurred_at
```

Generated `movement_id` values include a UTC run token and row number to avoid collisions between runs. Each output file is created without overwriting an existing file. `occurred_at` values represent recent synthetic events in UTC; they are **not** the FILE incremental watermark.

## Run from the repository root

```bash
# One new file, six data rows (default)
python3 scripts/source/sftp/generate_inventory_movement.py

# One new file, 100 rows
python3 scripts/source/sftp/generate_inventory_movement.py --rows 100

# Three new files with 1,000 rows each
python3 scripts/source/sftp/generate_inventory_movement.py --files 3 --rows 1000

# Generate under YYYY/MM/ to test recursive SFTP discovery
python3 scripts/source/sftp/generate_inventory_movement.py --nested --rows 10

# Choose an alternative local output directory
python3 scripts/source/sftp/generate_inventory_movement.py \
  --output-dir /tmp/inventory-movements --rows 10
```

By default, generated files go under:

```text
scripts/source/sftp/outbound/inventory/movements/
  inventory_movement_YYYYMMDDTHHMMSSZ.csv
```

When a filename already exists (or `--files` > 1 in the same second), the utility appends `_001`, `_002`, etc., still matching the pipeline's `inventory_movement_*.csv` wildcard. `--nested` stores new files in `YYYY/MM/` beneath the same movements root, matching the adapter's recursive discovery. The script doesn't change checked-in sample files; generated CSV files are gitignored.

## Deliver to SFTP and test Fabric

1. Generate new CSV files locally.
2. Upload them using the **producer** SFTP account to `/outbound/inventory/movements/` (preserve `YYYY/MM/` if using `--nested`). The script does **not** upload or authenticate to SFTP.
3. Confirm the **remote file Last Modified time** is in the intended UTC window. Avoid upload options that preserve an old source mtime when testing current-arrival behavior; some SFTP clients can preserve timestamps.
4. Run `pl_ingest_orchestrator` for the `inventory_movement` config (REGULAR), then verify Bronze rows, audit counts and the stored watermark. Files delivered after the object's run `p_start_time` belong to a later run.
5. Rerun REGULAR **without uploading additional files** to exercise no-new-data `SKIPPED` behavior. Generate/upload fresh files to exercise a new SUCCESS, or request an explicit UTC LOW/HIGH BACKFILL to reprocess an older range without watermark advance.

**Watermark contract:** the SFTP connector filters on **remote** `last_modified_time` with `LOW <= LastModified < HIGH`; the `YYYYMMDDTHHMMSSZ` filename and CSV `occurred_at` are informational, not checkpoint inputs. A file's local timestamp is not proof of its timestamp after SFTP upload.

**Safety:** use DEV/test SFTP only. The generator doesn't modify Control Plane, Bronze, or previous fixtures. The pipeline remains responsible for ingestion, skipping, auditing, and watermark advancement. Files retained under the SFTP source can be intentionally replayed by BACKFILL.
