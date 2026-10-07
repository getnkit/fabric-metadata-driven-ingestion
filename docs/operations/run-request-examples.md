# Top-level run request examples

`pl_ingest_orchestrator` accepts:

```text
p_run_requests : array
```

The default is an empty array.

## Run all active configurations

Use:

```json
[]
```

An empty array means:

```text
run every active ingestion configuration as REGULAR
```

Each config uses its persistent `load_strategy` from `control.ingestion_config`.

## Run an explicit subset

Each request specifies the config and execution intent. LOW/HIGH boundaries are
optional at the envelope level and are supplied only when the execution semantics
require them.

Example:

```json
[
  {
    "config_id": 1,
    "run_type": "REGULAR"
  },
  {
    "config_id": 5,
    "run_type": "BACKFILL",
    "lower_bound": "2026-09-01T00:00:00.000Z",
    "upper_bound": "2026-09-30T23:59:59.999Z"
  },
  {
    "config_id": 3,
    "run_type": "BACKFILL"
  }
]
```

In the seeded metadata, config 5 is INCREMENTAL and config 3 is FULL. Their
BACKFILL requests therefore have different scope shapes.

## Request contract

| Field | Required | Meaning |
| --- | --- | --- |
| `config_id` | Yes | `control.ingestion_config.ingestion_config_id` |
| `run_type` | Yes | `REGULAR` or `BACKFILL` |
| `lower_bound` | Conditional | Requested historical LOW boundary when required |
| `upper_bound` | Conditional | Requested historical HIGH boundary when required |

Rules:

- `load_strategy` is read from the ingestion config; callers do not override it.
- REGULAR + FULL: omit LOW/HIGH; if supplied, they must be empty.
- REGULAR + INCREMENTAL: omit LOW/HIGH; the pipeline derives its normal operational range from state.
- BACKFILL + FULL: omit LOW/HIGH; V1 rereads the full currently available source scope.
- BACKFILL + INCREMENTAL: both LOW and HIGH are required and must be non-empty.
- Missing optional bounds are normalized to empty strings by the Dispatcher before the request reaches the Controller.
- BACKFILL never advances an INCREMENTAL config's operational watermark/checkpoint.
- Every successful REGULAR/BACKFILL execution appends a new Bronze batch.
- An explicitly requested inactive configuration is recorded as `SKIPPED`; it does not move data or advance processing state.
- Malformed envelope fields are rejected before Dispatcher fan-out: `config_id` must be a positive integer, `run_type` must be REGULAR/BACKFILL, and any supplied LOW/HIGH value must be a string or null.
- Config-specific LOW/HIGH requirements are validated by the Object Controller after the ingestion configuration is resolved.
- A given `config_id` may appear at most once in one `p_run_requests` array; duplicates are rejected before Dispatcher fan-out.

A future historical FULL-snapshot requirement should add an explicit selector such
as `data_date`, snapshot ID, or source version. Do not reinterpret LOW/HIGH as a
historical snapshot identifier.
