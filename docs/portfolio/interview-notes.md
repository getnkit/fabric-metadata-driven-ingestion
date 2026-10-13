# Portfolio / Interview Walkthrough

Use this as a **review outline**, not a script to memorize without checking
the code. Keep architecture, implementation and runtime evidence separate.

## The 60-second explanation

> I built a metadata-driven **batch ingestion** framework in Microsoft Fabric.
> Instead of duplicating a Data Factory pipeline per source object, a SQL
> Control Plane stores the active configurations, connection references and
> incremental watermarks. One orchestrator dispatches each object through
> database or file adapters: SQL Server uses connector-native query-mode Copy,
> while SFTP files land as Binary first and a Notebook parses them into
> append-only Bronze Delta tables. Success finalization writes object-level
> audit and advances eligible watermarks transactionally with optimistic
> checks. I also implemented execution-scoped cleanup for failed Bronze writes
> and built a Power BI Operations Report from the audit views. The project is
> reproducible as a fresh DEV from Git, but cloud connections and stateful data
> still require separate environment setup or backups.

## What to show in five minutes

1. **Problem and metadata contract (45 sec):** Show
   `control.ingestion_config` and explain how one row selects source
   type, load strategy, target and optional Copy tuning.
2. **Pipeline topology (60 sec):** Start at `pl_ingest_orchestrator`;
   trace all-active/config pagination -> dispatcher -> controller ->
   router -> SQL Server or SFTP adapter.
3. **Two distinct ingestion paths (45 sec):** SQL query-mode Copy direct
   to Bronze; SFTP Binary Landing -> Notebook parsing -> Bronze Delta.
4. **Correctness and failure (75 sec):** Separate REGULAR vs BACKFILL,
   optimistic watermark finalization, SKIPPED/no-new-data behavior and
   `(_batch_id, _pipeline_run_id)` compensation.
5. **Operations and honest evidence (55 sec):** Open object audit and
   Desktop-authored Power BI Report; show recorded DEV metrics and limits.
6. **Reusability (20 sec):** Open the [rebuild guide](../operations/environment-rebuild.md)
   and show which settings are re-bound for a new workspace.

## Questions worth being able to answer

**Why a metadata-driven framework instead of one pipeline per table?**

It centralizes repeatable routing, state, status and error-handling contracts
while leaving connector-specific Copy logic in adapters. It also adds
complexity: configuration errors can affect many sources, so constraints,
validation and scoped audit are important.

**How do you prevent data loss on incremental runs?**

The adapter uses a durable LOW checkpoint and source/run HIGH boundary.
Only an eligible REGULAR successful finalize advances state; the stored
procedure guards against stale concurrent updates. SKIPPED/backfill paths
do not advance state. This is not a promise of end-to-end exactly-once
business records across all possible source change patterns.

**What happens when Copy fails after writing some Bronze rows?**

The compensation Notebook deletes only rows for that failed
`(_batch_id, _pipeline_run_id)` object execution. Successful batches
from other runs remain intact. When the state of finalization is ambiguous,
the recovery path does not assume a safe rollback.

**Why is SQL Server incremental not one monolithic pipeline?**

It separates watermark/no-new-data decisions in the adapter from nested
AUTO/TUNED Copy execution in the loader, preserving clear runtime boundaries
under Fabric's branching structure. A single Copy with
`parallelCopies=0` is not a safe replacement for AUTO because a DEV PoC
observed different actual parallelism when the property was omitted.

**Why not use a Notebook for every source?**

Fabric Copy provides a native connector/data-movement path for SQL Server.
A Notebook is valuable where file parsing and Delta-aware cleanup have
reusable code, not as an automatic replacement for every Copy Activity.

**Does the Power BI Report show master pipeline failures live?**

No. It reads terminal *object* audits through DirectQuery. A master
failure before object audit and RUNNING states are outside its data source.
Fabric Monitor/optional alerting cover a different operational concern.

**Can a new engineer recreate the environment from Git alone?**

Definitions, SQL schema, sample fixture scripts and instructions are in Git.
But Git cannot restore secret credentials, Fabric Connections, historical
Bronze rows or watermarks. A fresh DEV rebuild requires new cloud setup
and rebinding; a full state restore requires independent backups.

**How was AI used?**

AI-assisted drafting, code exploration, review and iterative refactoring
are compatible with owning engineering decisions. Describe *what you
personally verified and changed*, including the manually authored Power BI
Report, the Copy AUTO/zero PoC and run-level checks. Do not say that every
line was written without assistance or that AI suggestions were deployed
without review. Good ownership means being able to explain and defend
the outcome, not pretending assistance did not exist.

## Explicit limitations and future work

- Implemented source connectors: SQL Server and SFTP only.
- Implemented file parser: delimited text; not API/CDC/streaming.
- Target is Bronze; no complete Silver/Gold business transformation.
- No per-config lock, no general-purpose quarantine/DQ engine, no
  production-ready DR procedure or published SLA.
- Benchmark includes observed PoCs, but full controlled four-scenario
  performance evidence is still pending.

See [Architecture](architecture.md), [Evidence Register](evidence.md)
and the actual tracked Pipeline, SQL and Notebook definitions before
presenting stronger claims.
