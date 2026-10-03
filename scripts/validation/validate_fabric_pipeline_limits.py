#!/usr/bin/env python3
"""Validate Fabric pipeline artifacts against selected documented hard limits."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any, Iterable

MAX_ACTIVITIES = 120
MAX_PARAMETERS = 50
MAX_FOREACH_BATCH_COUNT = 50
MAX_EXPRESSION_CHARS = 8192
MAX_LOOKUP_ITEMS = 5000

WARN_ACTIVITIES = 100
WARN_PARAMETERS = 40
WARN_EXPRESSION_CHARS = 7000


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


def iter_expressions(node: Any) -> Iterable[str]:
    if isinstance(node, dict):
        if node.get("type") == "Expression" and isinstance(node.get("value"), str):
            yield node["value"]
        for value in node.values():
            yield from iter_expressions(value)
    elif isinstance(node, list):
        for value in node:
            yield from iter_expressions(value)


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    pipeline_paths = sorted(
        (repo_root / "fabric").glob("*.DataPipeline/pipeline-content.json")
    )

    errors: list[str] = []
    warnings: list[str] = []

    for path in pipeline_paths:
        payload = json.loads(path.read_text(encoding="utf-8"))
        properties = payload.get("properties", {})
        activities = list(iter_activities(properties.get("activities", [])))
        parameters = properties.get("parameters", {})

        display = path.parent.name.removesuffix(".DataPipeline")

        activity_count = len(activities)
        if activity_count > MAX_ACTIVITIES:
            errors.append(
                f"{display}: {activity_count} activities exceeds {MAX_ACTIVITIES}"
            )
        elif activity_count >= WARN_ACTIVITIES:
            warnings.append(
                f"{display}: {activity_count} activities is near {MAX_ACTIVITIES}"
            )

        parameter_count = len(parameters)
        if parameter_count > MAX_PARAMETERS:
            errors.append(
                f"{display}: {parameter_count} parameters exceeds {MAX_PARAMETERS}"
            )
        elif parameter_count >= WARN_PARAMETERS:
            warnings.append(
                f"{display}: {parameter_count} parameters is near {MAX_PARAMETERS}"
            )

        for activity in activities:
            if activity.get("type") == "ForEach":
                type_properties = activity.get("typeProperties", {})
                batch_count = type_properties.get("batchCount")
                if type_properties.get("isSequential") is True and "batchCount" in type_properties:
                    errors.append(
                        f"{display}/{activity.get('name')}: "
                        "sequential ForEach must omit batchCount"
                    )
                if isinstance(batch_count, int) and batch_count > MAX_FOREACH_BATCH_COUNT:
                    errors.append(
                        f"{display}/{activity.get('name')}: "
                        f"batchCount={batch_count} exceeds {MAX_FOREACH_BATCH_COUNT}"
                    )

        def validate_decision_nesting(
            nested_activities: Iterable[dict[str, Any]],
            parent_decision: str | None = None,
        ) -> None:
            for nested_activity in nested_activities:
                activity_type = nested_activity.get("type")
                activity_name = nested_activity.get("name")
                is_decision = activity_type in {"IfCondition", "Switch"}

                if is_decision and parent_decision in {"IfCondition", "Switch"}:
                    errors.append(
                        f"{display}/{activity_name}: "
                        f"{activity_type} cannot be nested inside {parent_decision}"
                    )

                next_parent = activity_type if is_decision else parent_decision
                tp = nested_activity.get("typeProperties", {})

                for key in (
                    "activities",
                    "ifTrueActivities",
                    "ifFalseActivities",
                    "defaultActivities",
                ):
                    nested = tp.get(key)
                    if isinstance(nested, list):
                        validate_decision_nesting(nested, next_parent)

                for case in tp.get("cases", []) or []:
                    nested = case.get("activities")
                    if isinstance(nested, list):
                        validate_decision_nesting(nested, next_parent)

        validate_decision_nesting(properties.get("activities", []))

        for expression in iter_expressions(payload):
            length = len(expression)
            if length > MAX_EXPRESSION_CHARS:
                errors.append(
                    f"{display}: expression length {length} exceeds "
                    f"{MAX_EXPRESSION_CHARS}"
                )
            elif length >= WARN_EXPRESSION_CHARS:
                warnings.append(
                    f"{display}: expression length {length} is near "
                    f"{MAX_EXPRESSION_CHARS}"
                )

        if display == "pl_master_ingestion":
            default_page_size = (
                parameters.get("p_config_page_size", {}).get("defaultValue")
            )
            if not isinstance(default_page_size, int):
                errors.append(
                    "pl_master_ingestion: p_config_page_size must have an integer default"
                )
            elif not 1 <= default_page_size <= MAX_LOOKUP_ITEMS:
                errors.append(
                    "pl_master_ingestion: p_config_page_size default must be "
                    f"between 1 and {MAX_LOOKUP_ITEMS}"
                )

    if warnings:
        print("WARNINGS")
        for warning in warnings:
            print(f"- {warning}")

    if errors:
        print("ERRORS")
        for error in errors:
            print(f"- {error}")
        return 1

    print(
        f"OK: validated {len(pipeline_paths)} Fabric pipeline artifact(s) "
        "against selected static platform limits."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
