#!/usr/bin/env python3
"""Run: python3 scripts/source/sftp/generate_inventory_movement.py
Creates one 6-row CSV locally; upload it to SFTP /outbound/inventory/movements/.
"""

import csv
from datetime import datetime, timezone
from pathlib import Path

ROWS = [
    ("BKK-3PL-01", "SKU000001", "RECEIPT", 25),
    ("BKK-3PL-01", "SKU000002", "SALE", -3),
    ("BKK-3PL-01", "SKU000003", "RETURN", 1),
    ("BKK-3PL-02", "SKU000007", "ADJUSTMENT", -2),
    ("BKK-3PL-02", "SKU000008", "RECEIPT", 40),
    ("BKK-3PL-02", "SKU000009", "SALE", -5),
]

now = datetime.now(timezone.utc)
folder = Path(__file__).resolve().parent / "outbound/inventory/movements" / now.strftime("%Y/%m")
folder.mkdir(parents=True, exist_ok=True)
path = folder / f"inventory_movement_{now:%Y%m%dT%H%M%S%fZ}.csv"

with path.open("x", newline="", encoding="utf-8") as file:
    writer = csv.writer(file, lineterminator="\n")
    writer.writerow(("movement_id", "warehouse_code", "sku", "movement_type", "quantity_change", "occurred_at"))
    for number, (warehouse, sku, movement_type, quantity) in enumerate(ROWS, start=1):
        writer.writerow((
            f"MOV{now:%Y%m%d%H%M%S%f}{number:02d}",
            warehouse, sku, movement_type, quantity,
            now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        ))

print(f"Created {path} ({len(ROWS)} rows)")
