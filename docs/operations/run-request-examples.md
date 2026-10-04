# Top-level run request examples

`pl_ingest_orchestrator` has one runtime selection parameter:

```text
p_run_requests : array
```

The default value is an empty array.

## Run all active configurations

Use:

```json
[]
```

An empty array means:

```text
run every active ingestion configuration as REGULAR
```

The orchestrator counts the active configurations, applies the configured page
size, and sends each page to `pl_ingest_config_page_dispatcher`.

Do not toggle `control.ingestion_config.is_active` merely to select a temporary
subset. `is_active` represents whether a configuration is operationally enabled.

## Run an explicit subset

Pass one object per requested configuration:

```json
[
  {
    "config_id": 1,
    "run_type": "REGULAR",
    "lower_bound": "",
    "upper_bound": ""
  },
  {
    "config_id": 5,
    "run_type": "BACKFILL",
    "lower_bound": "2026-09-01T00:00:00.000Z",
    "upper_bound": "2026-09-30T23:59:59.999Z"
  }
]
```

The dispatcher fans out exactly the supplied requests. Each object carries its
own execution intent, so one top-level run can mix REGULAR and BACKFILL work.

## Request contract

Each request object contains:

| Field | Meaning |
| --- | --- |
| `config_id` | `control.ingestion_config.ingestion_config_id` |
| `run_type` | `REGULAR` or `BACKFILL` |
| `lower_bound` | Optional historical LOW boundary |
| `upper_bound` | Optional historical HIGH boundary |

Rules:

- REGULAR must leave `lower_bound` and `upper_bound` empty.
- BACKFILL may use a pattern-specific historical scope.
- DATABASE + INCREMENTAL BACKFILL requires both LOW and HIGH.
- FILE + INCREMENTAL BACKFILL requires both LOW and HIGH and applies them to the
  source file Last Modified window.
- FULL + BACKFILL is not rejected by the generic controller. Historical snapshot
  selection, when required, is source-specific.
- For the current V1 contract, include a given `config_id` at most once in one
  `p_run_requests` array. Use separate top-level runs for multiple windows of
  the same configuration.

The array is a runtime pipeline parameter. It is not loaded from a YAML or JSON
configuration file. This document is the reusable reference/template.
