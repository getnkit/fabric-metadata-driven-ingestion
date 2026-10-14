# Experimental Evidence & Benchmark Test Plan

**Rule:** observed source logs/screenshots are different from estimates,
controlled comparisons, and future tests. Numbers below come from the
project's recorded DEV experiments and user-reviewed Fabric runs; they are
**not** independently repeated production load tests.

## Evidence currently recorded

| ID | Scope / setup | Observed outcome | Claim allowed |
| --- | --- | --- | --- |
| E01 | All-active DEV ingestion, 8 sample configs | 8 object terminal audits: 2 SUCCESS, 6 SKIPPED; 32 source/target rows in a documented light-workload comparison | Demonstrates mixed terminal outcomes and object audit in a sample DEV run |
| E02 | Dispatcher `fe_run_requests.batchCount=3` versus `8` on the documented light run (2026-10-11) | 9m29s vs 4m44s; both runs recorded 8 audits, 2 SUCCESS + 6 SKIPPED, and 32 source/target rows | Observed *this scenario* improving with bounded parallelism; **not** proof of general linear scaling or cost efficiency |
| E03 | Isolated SQL Server query-mode `DYNAMIC_RANGE` PoC on `benchmark.copy_source_partitioned` (10M rows), with `parallelCopies: 0` | Copy Succeeded; 10,000,000 read/written; `copyDuration=483s`; `throughput=23.08 MB/s`; `usedParallelCopies=1`, DIU=4; approximately 11.03 GB source bytes read | Explicit `0` is accepted at runtime in this setup, but does not imply service-managed AUTO |
| E04 | Same 10M source, omitted `parallelCopies` (AUTO) | **In-progress** snapshot reported `usedParallelCopies=4`; no completed duration or final throughput supplied | AUTO can choose parallelism differently; **do not** claim a final speedup vs E03 |
| E05 | Desktop-authored Ingestion Operations Report, Fabric DEV | Latest observed snapshot: 2 Source Systems; 8 Objects; 0 Failed Sources; filtered summary + object-history visual reviewed; user confirmed official Git Sync/report worked | Operational UI and live-deployment observation; not proof of every failure path or unseen batch state |

Reference docs: [Copy Performance](../architecture/database-copy-performance.md),
[Run Scope](../operations/run-request-examples.md) and
[Monitoring](../operations/monitoring-report.md).

### Important interpretation

- E02 runs are **small sample workload** with many SKIPPED objects;
  run scheduling/overheads can dominate the measured total time.
- E03 is a **separate PoC Copy Activity**, not a completed apples-to-apples
  comparison against the production-shaped AUTO/TUNED framework.
- E04 is an **interim snapshot**, not a finished run. No end-to-end time,
  completed COPY throughput or validated AUTO-versus-zero performance ratio.
- Do not write "tested at scale in production", "exactly once end-to-end",
  "supports CDC", or "automated environment disaster recovery" based on this
  evidence.

## Controlled performance suite to run later

Fixture source: `sql_benchmark_db`, SQL Server 2022 Developer on EC2.
Both `benchmark.copy_source_unpartitioned` and
`benchmark.copy_source_partitioned` contain **10,000,000 logically
equivalent rows** with a `CHAR(512)` payload; physical SQL Server layout
differs. Generator/DDL:
[scripts/source/benchmark-db](../../scripts/source/benchmark-db/README.md).

| Scenario selector | Physical source layout | Fabric Copy partition option | Partition key |
| --- | --- | --- | --- |
| `UNPARTITIONED_NONE` | Unpartitioned | NONE | n/a |
| `UNPARTITIONED_DYNAMIC` | Unpartitioned | DYNAMIC_RANGE | event_date |
| `PARTITIONED_NONE` | Partitioned by event_date | NONE | n/a |
| `PARTITIONED_DYNAMIC` | Partitioned by event_date | DYNAMIC_RANGE | event_date |

Test with omitted `parallelCopies` for AUTO. Compare an explicit **positive**
override separately if needed. An explicit `0` is a distinct PoC case and
must not be treated as AUTO.

**Capture, per run:** Pipeline/Activity Run ID, status, time window (UTC),
scenario, source row count, target row count, sink table/mode, Copy duration,
throughput, `usedParallelCopies`, DIUs, source bytes read, source CPU/IO,
Fabric capacity/load, and any error or retries. Confirm a **fresh or cleared
DEV target** before each append test, and preserve equivalent conditions.
Repeat each candidate sufficiently to assess run-to-run noise (for example
three times) instead of ranking single runs.

**Cost and environment cautions:** large tables consume EC2 EBS/SQL log and
Fabric resources; do not extrapolate a SQL Server Developer/EC2 DEV result to
production cost, scalability or enterprise SLAs.

## Screenshot / artifact capture checklist (not yet bundled)

| Suggested file | What the screenshot should establish |
| --- | --- |
| `assets/architecture-overview.png` | Architecture slide or Mermaid screenshot with sources/control/ingestion/audit |
| `assets/orchestrator-run.png` | Orchestrator and object-level runs for a real SUCCESS/SKIPPED batch |
| `assets/bronze-sample.png` | Bronze schema/lineage columns; no private or sensitive data |
| `assets/watermark-and-audit.png` | One audited run aligned to current watermark with IDs redacted where appropriate |
| `assets/powerbi-operations.png` | Desktop-authored final Report and slicer interactions |
| `assets/benchmark-copy.png` | Completed Copy run details with scenario, rows, duration and parallel copies |

**These files are proposed names, not existing images.** Add only actual,
reviewed screenshots after masking passwords, tenant-specific endpoints,
private hostnames, personal identities and credentials. For any public technical documentation, use synthetic data and no private client artifacts.

## Verified and outstanding test coverage

- [x] Metadata-driven SQL Server + SFTP batch ingestion implementation exists
- [x] FULL + INCREMENTAL routing with REGULAR + BACKFILL intent
- [x] Control/Audit SQL objects, append-only Bronze and compensation logic
- [x] Source-level monitoring Report created through Power BI Desktop
- [x] Fresh DEV rebuild instructions tracked in Git
- [ ] Independent clean-room workspace rebuild executed and signed off
- [ ] Complete 2x2 benchmark suite with repeated measured results
- [ ] Public screenshot bundle from verified artifacts
- [ ] Production-scale throughput, SLO and sustained reliability evidence

The unchecked entries are deliberately **not** represented as completed.
