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

Each REGULAR config then uses its configured `load_strategy` (FULL or
INCREMENTAL). The orchestrator counts active configurations, applies the
configured page size, and sends each page to
`pl_ingest_config_page_dispatcher`.

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
own execution intent, so one top-level run can mix normal REGULAR work with
historical BACKFILL work.

## Request contract

Each request object contains:

| Field | Meaning |
| --- | --- |
| `config_id` | `control.ingestion_config.ingestion_config_id` |
| `run_type` | `REGULAR` or `BACKFILL` |
| `lower_bound` | Historical LOW boundary for BACKFILL |
| `upper_bound` | Historical HIGH boundary for BACKFILL |

Rules:

- REGULAR must leave `lower_bound` and `upper_bound` empty.
- BACKFILL requires both `lower_bound` and `upper_bound` in the current V1
  contract.
- BACKFILL is not labeled FULL or INCREMENTAL. It is a separate run intent with
  its own historical scope.
- Current DATABASE backfill applies LOW/HIGH to a configured watermark field.
- Current FILE/SFTP backfill applies LOW/HIGH to source file Last Modified time.
- BACKFILL never advances the operational watermark/checkpoint.
- An explicitly requested inactive configuration is recorded as `SKIPPED`; it
  does not move data or advance processing state.
- For the current V1 contract, include a given `config_id` at most once in one
  `p_run_requests` array. Use separate top-level runs for multiple windows of
  the same configuration.

The array is a runtime pipeline parameter. It is not loaded from a YAML or JSON
configuration file. This document is the reusable reference/template.
