# Top-level run request examples

`pl_ingest_orchestrator` accepts:

```text
p_run_requests : array
p_source_system : string (optional; default "")
```

The default is an empty array. `p_source_system` defaults to an empty string.

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

## Run active configurations for one source system

Use the **same** top-level `pl_ingest_orchestrator` pipeline definition in a separate run:

```text
p_run_requests = []
p_source_system = "ECOMMERCE"
```

This selects only active ECOMMERCE configs (seeded IDs 1–6). Another independent
run with `p_source_system = "LOGISTICS_VENDOR"` selects active IDs 7–8.
Both runs receive different master Run IDs and generated Batch IDs. To execute
both scopes at midnight, use two schedules that invoke this same pipeline
with different parameters. A blank/whitespace-only source system is equivalent
to no filter (all active). The filter is trimmed and treated as an exact
metadata value according to the Control SQL Database collation.

If a nonblank `p_source_system` has **no active configs**, the paginator fails
with `NO_ACTIVE_SOURCE_CONFIGS` instead of silently returning SUCCESS.

### Scope and explicit-request validation

The three supported parameter combinations are:

| `p_source_system` | `p_run_requests` | Behavior |
| --- | --- | --- |
| `""` | `[]` | All active configs as REGULAR |
| Nonblank source system | `[]` | Only active configs for that source system as REGULAR |
| `""` | Nonempty array | Explicit config requests (REGULAR or BACKFILL) |

A nonblank `p_source_system` combined with a nonempty `p_run_requests` is
rejected at the master with `AMBIGUOUS_RUN_SCOPE`, before any child ingestion
starts. The master does **not** silently filter explicit requests or ignore the
scope. Existing duplicate-request validation remains unchanged for explicit mode.

### Execution and concurrency boundaries

The master definition now permits up to **2 concurrent master runs** in DEV,
so separate ECOMMERCE and LOGISTICS_VENDOR scopes may overlap. The shared
Dispatcher remains `fe_run_requests` with static `batchCount = 3` **per run**;
Phase B dynamic per-source concurrency is intentionally out of scope.
Do not schedule overlapping runs for the **same source system** or trigger
All Active concurrently with a source-specific run: global master concurrency
is not a per-source lock. Overlapping configs can duplicate FULL Bronze data
or cause optimistic Watermark conflicts for INCREMENTAL. If you need to run
more than two independent source scopes simultaneously, review master
concurrency, Fabric capacity, and non-overlapping schedule design first.

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
- Source-system filtering is used only in the All Active paginator path; explicit requests never inherit or override the source-system filter.

A future historical FULL-snapshot requirement should add an explicit selector such
as `data_date`, snapshot ID, or source version. Do not reinterpret LOW/HIGH as a
historical snapshot identifier.
