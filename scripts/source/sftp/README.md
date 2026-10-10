# SFTP source fixtures

From the repository root, run:

```bash
python3 scripts/source/sftp/generate_inventory_movement.py
```

This creates **one new 6-row CSV per run** under
`scripts/source/sftp/outbound/inventory/movements/YYYY/MM/` (UTC year/month),
with no arguments or
third-party dependencies. Existing files are never overwritten. The filename
and each `movement_id` include the current UTC microsecond timestamp to
avoid collisions across runs. The six SKUs belong to the existing inventory
snapshot fixture; repeating a SKU in new movement events is expected.
The CSV schema matches the existing `inventory_movement_*.csv` samples.

Upload the generated CSV to the **SFTP server** at
`/outbound/inventory/movements/YYYY/MM/` with the producer account,
preserving the same relative year/month folders. The script
writes locally only; it does not upload files or change Fabric state.

**Watermark:** Fabric FILE INCREMENTAL uses the **remote SFTP file
`last_modified_time`** (`LOW <= LastModified < HIGH`), not the filename,
`movement_id` or row `occurred_at`. Ensure the upload does not preserve
an older file timestamp. After testing a new-file SUCCESS, rerun without
uploading anything to test `SKIPPED`.

The three versioned inventory-movement fixtures are organized under
`2026/09/` (two files) and `2026/10/` (one file). The Fabric SFTP
Copy uses recursive discovery and PreserveHierarchy, so no pipeline
changes are required to ingest these nested folders.
