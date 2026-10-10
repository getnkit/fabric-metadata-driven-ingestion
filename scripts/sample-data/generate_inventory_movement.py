#!/usr/bin/env python3
"""Generate fresh SFTP inventory_movement CSV fixtures (Python stdlib only).

Producer-side test utility: it writes local files only, without uploading to
SFTP or changing Fabric pipeline/control-plane state.
"""

import argparse
import csv
from datetime import datetime, timedelta, timezone
from pathlib import Path

COLUMNS = (
    "movement_id",
    "warehouse_code",
    "sku",
    "movement_type",
    "quantity_change",
    "occurred_at",
)

MOVEMENT_TYPES = (
    ("RECEIPT", 25),
    ("SALE", -3),
    ("RETURN", 1),
    ("ADJUSTMENT", -2),
    ("RECEIPT", 40),
    ("SALE", -5),
)

DEFAULT_OUTPUT_DIR = (
    Path(__file__).resolve().parents[2]
    / "sample-data"
    / "sftp"
    / "outbound"
    / "inventory"
    / "movements"
)


def positive_int(value: str) -> int:
    try:
        number = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be a positive integer") from exc
    if number < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return number


def generate_files(output_dir: Path, rows: int, files: int, nested: bool) -> list[Path]:
    run_time = datetime.now(timezone.utc)
    if nested:
        output_dir = output_dir / run_time.strftime("%Y") / run_time.strftime("%m")
    output_dir.mkdir(parents=True, exist_ok=True)

    generated = []
    # A UTC microsecond run token prevents movement_id collisions between runs.
    run_token = run_time.strftime("%Y%m%d%H%M%S%f")
    filename_timestamp = run_time.strftime("%Y%m%dT%H%M%SZ")

    for file_index in range(files):
        stem = f"inventory_movement_{filename_timestamp}"
        # Never overwrite a static or previously generated fixture.
        sequence = file_index
        while True:
            suffix = "" if sequence == 0 else f"_{sequence:03d}"
            path = output_dir / f"{stem}{suffix}.csv"
            try:
                handle = path.open("x", newline="", encoding="utf-8")
                break
            except FileExistsError:
                sequence += 1

        try:
            with handle:
                writer = csv.writer(handle, lineterminator="\n")
                writer.writerow(COLUMNS)
                for row_index in range(rows):
                    record_index = file_index * rows + row_index
                    movement_type, change = MOVEMENT_TYPES[record_index % len(MOVEMENT_TYPES)]
                    warehouse = f"BKK-3PL-{1 + record_index % 2:02d}"
                    sku = f"SKU{1 + record_index % 4000:06d}"
                    # Source event times are recent UTC instants, not SFTP watermarks.
                    occurred_at = (run_time - timedelta(seconds=rows - row_index - 1)).strftime(
                        "%Y-%m-%dT%H:%M:%SZ"
                    )
                    writer.writerow(
                        (
                            f"MOV{run_token}_{record_index + 1:06d}",
                            warehouse,
                            sku,
                            movement_type,
                            change,
                            occurred_at,
                        )
                    )
        except Exception:
            path.unlink(missing_ok=True)
            raise
        generated.append(path)
    return generated


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create inventory_movement_*.csv files for SFTP incremental tests."
    )
    parser.add_argument("--rows", type=positive_int, default=6, help="Rows per file (default: 6).")
    parser.add_argument("--files", type=positive_int, default=1, help="Files per run (default: 1).")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Local movements root (default: repo sample-data/sftp/outbound/inventory/movements).",
    )
    parser.add_argument(
        "--nested", action="store_true", help="Generate under YYYY/MM/ to test recursive SFTP discovery."
    )
    args = parser.parse_args()
    if args.rows * args.files > 1_000_000:
        parser.error("generate at most 1,000,000 rows per invocation")

    for path in generate_files(args.output_dir, args.rows, args.files, args.nested):
        print(f"Created {path} ({args.rows} data rows)")
    print("Upload to the corresponding SFTP /outbound/inventory/movements/ path before running Fabric.")


if __name__ == "__main__":
    main()
