#!/usr/bin/env python3
"""Validate the current Azure SQL metadata-driven copy-tuning contract."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any, Iterable


WORKERS = (
    "pl_ingest_azure_sql_full",
    "pl_load_azure_sql_incremental",
)


def iter_activities(activities: Iterable[dict[str, Any]]) -> Iterable[dict[str, Any]]:
    for activity in activities:
        yield activity
        tp = activity.get("typeProperties", {})
        for key in ("activities", "ifTrueActivities", "ifFalseActivities", "defaultActivities"):
            nested = tp.get(key)
            if isinstance(nested, list):
                yield from iter_activities(nested)
        for case in tp.get("cases", []) or []:
            nested = case.get("activities")
            if isinstance(nested, list):
                yield from iter_activities(nested)


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    errors: list[str] = []

    for worker in WORKERS:
        path = repo_root / "fabric" / f"{worker}.DataPipeline" / "pipeline-content.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        parameters = payload.get("properties", {}).get("parameters", {})
        activities = list(iter_activities(payload.get("properties", {}).get("activities", [])))
        by_name = {a.get("name"): a for a in activities}

        for name in (
            "p_copy_partition_option",
            "p_copy_partition_column",
            "p_copy_parallel_copies",
        ):
            if name not in parameters:
                errors.append(f"{worker}: missing parameter {name}")

        auto = by_name.get("copy_source_to_bronze_auto")
        tuned = by_name.get("copy_source_to_bronze_tuned")
        if auto is None:
            errors.append(f"{worker}: missing copy_source_to_bronze_auto")
        if tuned is None:
            errors.append(f"{worker}: missing copy_source_to_bronze_tuned")

        if auto is not None and "parallelCopies" in auto.get("typeProperties", {}):
            errors.append(f"{worker}: AUTO copy must omit parallelCopies")

        if tuned is not None:
            parallel = tuned.get("typeProperties", {}).get("parallelCopies", {})
            if parallel.get("value") != "@pipeline().parameters.p_copy_parallel_copies":
                errors.append(
                    f"{worker}: tuned copy must use p_copy_parallel_copies"
                )

        for copy_name, activity in (
            ("AUTO", auto),
            ("TUNED", tuned),
        ):
            if activity is None:
                continue
            source_text = json.dumps(
                activity.get("typeProperties", {}).get("source", {}),
                ensure_ascii=False,
            )
            if "?DfDynamicRangePartitionCondition" not in source_text:
                errors.append(
                    f"{worker}: {copy_name} copy missing dynamic-range placeholder"
                )
            if "p_copy_partition_column" not in source_text:
                errors.append(
                    f"{worker}: {copy_name} copy missing partition-column binding"
                )
            if "DynamicRange" not in source_text or "'None'" not in source_text:
                errors.append(
                    f"{worker}: {copy_name} copy missing NONE/DYNAMIC_RANGE routing"
                )

        guard = by_name.get("if_valid_copy_options")
        if guard is None:
            errors.append(f"{worker}: missing copy-option validation guard")

    if errors:
        print("ERRORS")
        for error in errors:
            print(f"- {error}")
        return 1

    print(
        "OK: Azure SQL copy tuning contract uses service-managed AUTO by default "
        "and metadata-driven dynamic-range partitioning."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
