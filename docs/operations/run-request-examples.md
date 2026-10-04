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

Each request specifies the config and execution intent.

Example:

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
  },
  {
    "config_id": 3,
    "run_type": "BACKFILL",
    "lower_bound": "",
    "upper_bound": ""
  }
]
```

In the seeded metadata, config 5 is INCREMENTAL and config 3 is FULL. Their BACKFILL requests therefore have different scope shapes.

## Request contract

| Field | Meaning |
| --- | --- |
| `config_id` | `control.ingestion_config.ingestion_config_id` |
| `run_type` | `REGULAR` or `BACKFILL` |
| `lower_bound` | Requested historical LOW boundary when required |
| `upper_bound` | Requested historical HIGH boundary when required |

Rules:

- `load_strategy` is read from the ingestion config; callers do not override it.
- REGULAR + FULL: LOW/HIGH must be empty.
- REGULAR + INCREMENTAL: LOW/HIGH must be empty; the pipeline derives its normal operational range from state.
- BACKFILL + FULL: LOW/HIGH must be empty; V1 rereads the full currently available source scope.
- BACKFILL + INCREMENTAL: both LOW and HIGH are required.
- BACKFILL never advances an INCREMENTAL config's operational watermark/checkpoint.
- Every successful REGULAR/BACKFILL execution appends a new Bronze batch.
- An explicitly requested inactive configuration is recorded as `SKIPPED`; it does not move data or advance processing state.
- For the current V1 contract, include a given `config_id` at most once in one `p_run_requests` array.

A future historical FULL-snapshot requirement should add an explicit selector such as `data_date`, snapshot ID, or source version. Do not reinterpret LOW/HIGH as a historical snapshot identifier.
