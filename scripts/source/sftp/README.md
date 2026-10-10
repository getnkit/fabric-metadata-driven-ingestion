# SFTP source fixtures

From the repository root, run:

```bash
python3 scripts/source/sftp/generate_inventory_movement.py
```

This creates **one new 6-row CSV per run** in
`scripts/source/sftp/outbound/inventory/movements/`, with no arguments or
third-party dependencies. Existing files are never overwritten. The filename
and each `movement_id` include the current UTC microsecond timestamp to
avoid collisions across runs. The six SKUs belong to the existing inventory
snapshot fixture; repeating a SKU in new movement events is expected.
The CSV schema matches the existing `inventory_movement_*.csv` samples.

Upload the generated CSV to the **SFTP server** at
`/outbound/inventory/movements/` with the producer account. The script
writes locally only; it does not upload files or change Fabric state.

**Watermark:** Fabric FILE INCREMENTAL uses the **remote SFTP file
`last_modified_time`** (`LOW <= LastModified < HIGH`), not the filename,
`movement_id` or row `occurred_at`. Ensure the upload does not preserve
an older file timestamp. After testing a new-file SUCCESS, rerun without
uploading anything to test `SKIPPED`.

The SFTP adapter continues to support recursive subfolders when external
sources deliver them, but this demo generator uses only the flat folder.
