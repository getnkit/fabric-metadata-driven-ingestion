# Project Handoff — Fabric Metadata-Driven Pipelines Portfolio

> **Initial working snapshot:** 2026-10-25 (Asia/Bangkok); verify live GitHub HEAD before continuing  
> **Purpose:** Preserve the implementation boundary, prior design decisions, evidence inventory, documentation strategy, and next actionable work when continuing in a new ChatGPT conversation.  
> **Scope:** Personal GitHub portfolio only, separate from client delivery work.  
> **Storage:** Temporary public `.project-handoff/` folder. Do not publish credentials or private environment-specific identifiers.  
> **Status at handoff:** Framework and D01/D02 diagrams are complete for the current portfolio scope; 58 screenshots and 2 SVG diagrams have been committed and grouped on GitHub. **Visual evidence curation, composite authoring, Markdown image insertion, and final QA are still pending.**

## 0. How to use this handoff

1. In a new conversation, read `PROJECT_HANDOFF.md`, `EVIDENCE_INVENTORY.csv`, `SCREENSHOT_IMPLEMENTATION_PLAN.md`, and `CONTINUATION_PROMPT.md` directly from the live GitHub `.project-handoff/` folder rather than relying on old downloaded copies.
2. Inspect the **current** GitHub repository and branch/commit before changing files. The SHAs and counts here describe a snapshot, not a permanent lock.
3. Prioritize a **filename-first, low-effort, batch-by-batch review**. Don't open all 58 screenshots just to re-infer categories already established.
4. Never confuse **a file's presence** with evidence acceptance, nor **a planned/composite artifact** with an artifact that exists.
5. Don't begin redesigning the completed architecture, D01, or D02 unless an actual technical inconsistency is found.
6. The user authorized this sanitized temporary working handoff in the public GitHub repository. Do not commit detailed private evidence logs, credentials, secret values, or private environment-specific IDs. It is working context, not portfolio documentation.

## 1. Project identity and source of truth

- **Repository:** `https://github.com/getnkit/fabric-metadata-driven-pipelines`
- **Branch last checked:** `main`
- **Pre-handoff HEAD:** `9f17c1b2caab2488efbb994cbf085abf21b5c227` (historical baseline, not a permanent HEAD)
- **Most recent organizing commit:** `docs: organize evidence screenshots by scenario and category`
- **Preceding asset-upload commit:** `83d58c3431ac70311998e653c265f46b4596d13b`, `docs: add evidence screenshots and technical diagrams`
- **Owner/account:** Personal GitHub account `getnkit`. Use this personal repository rather than a separate work account.
- **Local synchronization after assistant's direct GitHub commit:** `git pull --ff-only origin main` (only if local worktree is clean/fast-forward is applicable).
- **GitHub is authoritative** for checked-in code, item definitions, docs, and committed assets. This handoff is authoritative for discussion decisions, intended evidence handling, user preferences, and the snapshot status—not a substitute for source-code verification.

**Do not mix projects:** This personal portfolio is separate from client delivery work. Do not introduce client information, credentials, client connection IDs, or unverifiable claims into the public repository.

## 2. Core goal and architecture (checked against current README/design guide)

Goal: Show how to implement **reusable, metadata-driven batch ingestion** in Microsoft Fabric from SQL Server and SFTP sources, with centrally managed configuration, audited object runs, safe incremental checkpoints, failure compensation, and operational monitoring.

### Logical responsibility groups

| Group | Technology | Responsibility |
|---|---|---|
| Control & Audit | Microsoft Fabric SQL Database | `control.connection_settings`, `control.ingestion_config`, `control.pipeline_watermarks`, `audit.ingestion_log`; validation/finalization procedures; read-only monitoring views |
| Orchestration | Microsoft Fabric Data Factory Data Pipelines | Request selection, active-config pagination, dispatcher, per-object validation and DATABASE/FILE routing, physical adapters, recovery |
| Data | Fabric Lakehouse (Bronze Delta), source-specific Copy/Notebook | SQL Server query-mode Copy to Bronze; SFTP Binary Copy to Landing, then Notebook parse/append to Bronze |

The three groups are **logical responsibilities**, not isolated systems. No claim of cross-service distributed transaction. `README.md` already contains an architecture overview illustration (`docs/assets/architecture-overview.svg`) and reviewed navigation; **do not rewrite README wholesale**.

### Implemented pipeline graph (check code for exact behavior)

- Entry: `pl_ingest_orchestrator` (supported external entry point).
- Select active configs: `pl_ingest_config_paginator` → `pl_ingest_config_dispatcher` → `pl_ingest_object_controller`.
- Route DATABASE: `pl_ingest_database_router` → `pl_ingest_sql_server_full_adapter` **or** `pl_ingest_sql_server_incremental_adapter` → `pl_ingest_sql_server_incremental_loader` (for INCREMENTAL).
- Route FILE: `pl_ingest_file_router` → `pl_ingest_sftp_full_adapter` **or** `pl_ingest_sftp_incremental_adapter`.
- Conditional incremental-finalization recovery: `pl_ingest_incremental_finalize_recovery` (not generally attached to FULL paths).
- Notebooks: `nb_load_file_landing_to_bronze`, `nb_cleanup_bronze_batch_rows`, `nb_cleanup_landing_batch_files`.

Source adapters are implemented for **SQL Server** and **SFTP** only. File parsing currently supports **`DELIMITED_TEXT`**; do not imply active JSON/Parquet, Oracle, Kafka/streaming, etc. SQL Server uses Copy rather than forcing Spark for relational extraction. The `p_source_system` optional source filter and `p_run_requests` array are different dispatch modes; combining nonempty explicit requests with nonblank source scope yields `AMBIGUOUS_RUN_SCOPE`.

### Semantics that must not drift

- Two independent dimensions:
  - Configured `load_strategy`: `FULL | INCREMENTAL`
  - Execution `run_type`: `REGULAR | BACKFILL`
- **`RERUN` is not a framework run_type.** Fabric Retry/Rerun is a separate platform execution recovery concept.
- **REGULAR + INCREMENTAL:** obtains committed LOW, determines source/run HIGH, advances the watermark only after eligible successful SQL finalization.
- **BACKFILL + INCREMENTAL:** uses requested historical LOW/HIGH, appends a new Bronze batch, **never advances operational watermark**.
- **FULL (REGULAR or BACKFILL):** appends current full source scope; no incremental checkpoint. BACKFILL FULL is *not* historical point-in-time snapshot.
- **No-new-data SKIPPED:** no Bronze append, no checkpoint advancement.
- **Bronze append-only for successful batches**; an overlapping replay may append a separate batch. Never claim global exactly-once business-record semantics.
- **Compensating cleanup on failure** scopes to **both** `_batch_id` and `_pipeline_run_id`. Distinguish a physical write failure from a possibly committed SQL finalizer whose activity reported failure; recover using durable audit outcome. Don't call it a distributed transaction.
- SQL Server timestamp `_ingestion_timestamp` is typed from source query (`DATETIME2(3)`); FILE reader uses Notebook-generated ingestion metadata. FILE incremental checkpoint based on remote file last-modified timestamp, not CSV payload date.

### Monitoring caveats

- Git-tracked Power BI items: `sm_ingestion_operations` and `rpt_ingestion_operations`, implemented/validated in DEV; omitted intentionally from **D02** because that image scopes to core ingestion environment binding.
- Power BI report reads **terminal object audits** in Fabric SQL Database. It is *not* a master-run audit or live RUNNING monitor. Pre-dispatch failures can have no object audit; inspect Fabric Monitor.
- Optional Fabric Activator DEV experiment observed failure event detection/rule action but **did not independently verify recipient inbox delivery**. Do not claim end-to-end alert delivery.

## 3. Runtime environment and D02 binding decisions

`vl_ingestion_connections` uses five `String` variables in the active workspace Value Set (currently DEV):

1. `ingestion_control_connection_id` — Fabric Control SQL **Connection ID**.
2. `ingestion_control_item_id` — Fabric SQL Database **Item ID**.
3. `ingestion_control_workspace_id` — containing **Workspace ID**.
4. `pipeline_invoke_connection_id` — Invoke Pipeline **Connection ID**.
5. `notebook_execution_connection_id` — Notebook execution **Connection ID**.

Separate source and target logical-resource bindings in `control.connection_settings` (source Connection refs and target Lakehouse Connection / Workspace / Item refs). Permissions and credentials are environment-specific; they are not backed up by Git item definitions. Same-workspace Fabric Pipeline and Notebook item references can use `.platform` logical IDs and matching zero GUID workspace references; **verify correct dependency remapping after sync**. Do not treat Fabric item IDs as Fabric Connection IDs.

**DEV implemented; UAT and PROD are Design only.** There is no proven UAT/PROD deployment, and no need to construct fake UAT/PROD UI screenshots. Variable Library UI screenshot was evaluated and intentionally **excluded from publishable evidence**; D02 plus runbook sufficiently describe the concept.

## 4. D01 and D02 — design decisions closed

Both editable SVGs are committed in `docs/assets/diagrams/`:

- **D01:** `d01-control-audit-er.svg` — title **“Control & Audit Data Model”**, subtitle **“Microsoft Fabric SQL Database”**. Keep two-level heading; don't change to a long one-line title solely to mimic D02. Depicts 4 core tables, FK and logical audit relationship, with design notes.
- **D02:** `d02-environment-binding.svg` — **“Environment Binding Architecture in Microsoft Fabric”**, title only (no platform subtitle). Shows **five scoped shared item definition types**: Data Pipelines, Notebooks, Variable Library, SQL Database, Lakehouse. Power BI was purposefully omitted from both shared-definition chips and per-workspace binding cards for this ingestion-specific architecture image (Power BI **still exists in repository**).
  - Workspace tiles: **DEV Implemented**, **UAT Design only**, **PROD Design only**. UAT/PROD state labels and sidebars styled in neutral gray; the Shared/Environment-specific meaning of other colors remains.
  - Three per-workspace binding cards: **Variable Library Values**, **Source & Target Resource Bindings**, **Permissions & Credentials**. Distinct **Dependency Auto-binding** note explains logical same-workspace item links vs environment-dependent connection IDs.
  - Label: **“Configure or verify per workspace”**. Do not imply rebinding always required after every sync if values already correct.
- D01 and D02 are considered **finalized**; no extra UI screenshots needed to prove D02 conceptual architecture.
- Editable diagrams must remain **real editable SVG**, not raster illustrations from an image generator. If revised later, provide SVG and PNG rendered **from the exact SVG** and visually inspect both.

## 5. Evidence asset snapshot — 58 screenshots + 2 diagrams

**Important:** At handoff, screenshots were **sorted using names and user notes only**. The 58 image bodies were **not** exhaustively inspected. A filename can indicate the intended claim, never prove that the image shows a successful test or contains no sensitive details.

Current structure:

```text
docs/assets/
├── architecture-overview.svg
├── diagrams/
│   ├── d01-control-audit-er.svg
│   └── d02-environment-binding.svg
└── screenshots/
    ├── core/                                10 screenshots
    ├── performance/                          3 direct screenshots
    │   └── source-config/                    3 PX screenshots
    └── supporting/
        ├── s1-orchestration/                22 CX screenshots
        ├── s2-no-new-data/                   4 CX screenshots
        ├── s3-sql-incremental/               3 CX screenshots
        ├── s4-sftp-incremental/              4 CX screenshots
        ├── s5-backfill/                      3 CX screenshots
        └── optional/
            ├── o01-end-to-end/               1 CX screenshot
            ├── o02-file-row-count/           2 CX screenshots
            └── o05-source-scope/             3 CX screenshots
```

**Counts:** 10 + 3 + 3 + 22 + 4 + 3 + 4 + 3 + 1 + 2 + 3 = **58**. Two SVG diagrams, **60 total committed visual assets**. Every screenshot was moved by Git path only—original PNG filename and Git Blob content preserved. No flat screenshots remain at `docs/assets/screenshots/*.png`.

`EVIDENCE_INVENTORY.csv` records individual current paths, batch/scenario tags, likely candidate, and unreviewed status. Prefer inventory/`git ls-files` over rereading all images to locate things.

### 5.1 Planned candidates and exact user status

**Core — C01 to C16:**

| Candidate | Intended filename | Snapshot status |
|---|---|---|
| C01 | `c01-control-metadata.png` | Direct file present; visual review pending |
| C02 | `c02-logical-connections.png` | Direct file present; visual review pending |
| C03 | `c03-master-orchestration.png` | Direct file present; visual review pending |
| C04 | `c04-object-routing.png` | **No single C04 file**; user chose **multiple separate captures** (S1 CX group) |
| C05 | `c05-sql-server-copy-execution.png` | Direct file present; visual review pending |
| C06 | `c06-sql-bronze-lineage.png` | Direct file present; visual review pending |
| C07 | `c07-sftp-ingestion-flow.png` | **No single C07 file**; user chose **multiple separate captures** (S1 CX group) |
| C08 | `c08-sftp-landing.png` | Direct file present; visual review pending |
| C09 | `c09-sftp-bronze-lineage.png` | Direct file present; visual review pending |
| C10 | `c10-no-new-data-skipped.png` | **Pending composite** from S2 CX group |
| C11 | `c11-sql-server-incremental.png` | **Pending composite** from S3 CX group |
| C12 | `c12-sftp-new-file-incremental.png` | **Pending composite** from S4 CX group |
| C13 | `c13-incremental-backfill.png` | **Pending composite** from S5 CX group |
| C14 | `c14-ambiguous-run-scope.png` | Direct file present; visual review pending |
| C15 | `c15-operations-report.png` | Direct file present; visual review pending |
| C16 | `c16-operations-filter.png` | Direct file present; visual review pending |

**Performance — P01 to P05:**

| Candidate | Intended filename | Snapshot status |
|---|---|---|
| P01 | `p01-benchmark-config.png` | **Use multiple separate source-config screenshots** (`px-s8-b1/b2/b3-config.png`), not necessarily a single P01 |
| P02 | `p02-query-none.png` | Direct file present; visual review pending |
| P03 | `p03-query-dynamic-range-auto.png` | Direct file present; visual review pending |
| P04 | `p04-query-dynamic-range-tuned.png` | Direct file present; visual review pending |
| P05 | `p05-query-mode-performance-comparison.png` | **Not yet created**; user wants AI assistance for a comparison visualization **derived only from real benchmark measurements**; no invented metrics or fabricated benchmark conclusions |

**Optional — O01 to O05:**

| Candidate | Intended filename | Snapshot status |
|---|---|---|
| O01 | `o01-end-to-end-trace.png` | Pending composite from `cx-o01-audit.png` and potentially other real execution images |
| O02 | `o02-file-vs-row-count.png` | Pending composite from Binary Copy and Notebook parse screenshots |
| O03 | `o03-full-append-history.png` | **SKIP / dropped by user** |
| O04 | `o04-copy-performance-details.png` | **SKIP / dropped by user** |
| O05 | `o05-source-scoped-run.png` | Pending composite from 3 source-scope screenshots |

**D01 / D02:** real SVGs exist and are finalized; intended Markdown integration is pending.

### 5.2 What S1–S5 mean (do not misinterpret duplicates)

- **S1 — orchestration and routing:** S1 CX names capture config pagination, master details, Dispatcher, Object Controller DATABASE/FILE, routers, SFTP incremental adapter, SQL Server FULL adapter. Supports C04/C07 as **several direct images**, not blindly one enormous composite.
- **S2 — no-new-data incremental:** audit `SKIPPED`, no Bronze append, checkpoint **unchanged**. Supports C10 composite. `cx-s2-watermark-before.png` and `cx-s2-watermark-after.png` have the **exact same Git Blob SHA**. This is compatible with expected unchanged state and **not evidence of failure**; however, byte-identical files do not independently establish that two separate screenshots were taken. Preserve both and be accurate in captions.
- **S3 — SQL Server incremental success:** success audit + Watermark Before/After. Expected eligible REGULAR success advances operational watermark. Supports C11. Confirm actual IDs/values before stating specifics.
- **S4 — SFTP new-file incremental:** success audit + new-file Bronze lineage + Watermark Before/After. Supports C12. Confirm actual remote last-modified bounds before writing a strong caption.
- **S5 — explicit historical BACKFILL:** audit BACKFILL and checkpoint **unchanged** even if successful append. Supports C13. `cx-s5-watermark-before.png` and `cx-s5-watermark-after.png` are exact same Git Blob. Expected invariant; same caveat about separate captures. Do **not** assert S5 advances the operational watermark.
- **S8 — performance setup:** PX B1/B2/B3 config screenshots plus P02–P04 recorded results. Do not infer B1/B2/B3's precise configuration solely from filenames; inspect actual configuration and measured metrics before P05.

### 5.3 Screenshot quality contract

1. Screenshot from an actual completed execution or persisted real state; capture master/object Run IDs and Batch IDs where needed.
2. Crop irrelevant UI without changing or inventing outcomes; any composite must use **real** source screenshots and be explicitly labeled a **Composite**.
3. Don't expose credentials, tokens, connection strings, personal IDs, or confidential business data. **Public repository currently contains images; no visual privacy audit has yet been completed in this workflow. Perform a proportional safety scan before prominently publishing/linking selected images.**
4. Caption tells **what an artifact proves** (e.g. final audit and checkpoint non-advancement), not just what UI it shows.
5. `evidence-log.csv` is optional **local/private working metadata**, useful for IDs and provenance; don't backfill unavailable IDs by guessing, and don't commit environment GUIDs unnecessarily.
6. If screenshot A and B support the same claim, use the clearer one. A guide need not include every image in the archive.

## 6. Performance facts and claim guardrails

See `docs/architecture/database-copy-performance.md`; DO NOT rely solely on this summary if interpreting new metrics.

- SQL Server source: SQL Server 2022 Developer on EC2. A separate benchmark database `sql_benchmark_db` includes two 10,000,000-row fixture tables with equal logical data but different **source physical layouts** (unpartitioned vs monthly partitioned); they are distinct from the **Fabric Copy partition execution strategy** (`NONE` or `DYNAMIC_RANGE`).
- SQL Server Copy in this framework uses **query mode**; source metadata `copy_options` may specify `partition_option = NONE | DYNAMIC_RANGE`, explicit partition column for dynamic range, optional positive `parallel_copies` override.
- **AUTO and explicit `parallelCopies = 0` are not equivalent.** AUTO route omits the `parallelCopies` property. A pipeline parameter value of 0 is an internal routing sentinel, **never** a value forwarded to the Copy activity. Positive override uses a tuned branch.
- Existing documented 2026-10-12 DEV PoC: **explicit zero** completed 10M rows, usedParallelCopies=1, CopyDuration=483 s, throughput ≈23.08 MB/s, used DIUs=4; native AUTO was observed **in progress**, usedParallelCopies=4. This observation proves differing parallelism in that test, not a completed comparative AUTO speedup.
- Source CPU/memory, bytes/rows, elapsed time, used parallel copies and DIUs, Fabric Capacity, target pre-run state all matter. For P05, use **completed and comparable actual runs** and document limits, not unverified speedup/cost claims.
- Do not turn a metadata configuration example such as `parallel_copies=8` into a benchmark-derived recommendation.

## 7. Documentation integration map — user's existing plan

**Do not immediately publish every candidate.** Integrate the selected, reviewed subset:

| Existing Markdown document | Planned image candidates |
|---|---|
| `docs/guides/control-plane.md` | C01, C02, D01 |
| `docs/guides/pipeline-orchestration.md` | C03, C04, O05 |
| `docs/guides/sql-server-database-ingestion.md` | C05, C06, C11 |
| `docs/guides/sftp-file-ingestion.md` | C07, C08, C09, C12 |
| `docs/architecture/generic-incremental-watermark.md` | C10 |
| `docs/operations/retry-rerun-backfill.md` | C13, O03 (but **O03 skipped**, do not publish) |
| `docs/operations/run-request-examples.md` | C14 |
| `docs/operations/monitoring-report.md` | C15, C16 |
| `docs/architecture/database-copy-performance.md` | P01–P05, O04 (but **O04 skipped**, do not publish) |
| `docs/architecture/framework-overview.md` | O01 |
| `docs/architecture/file-ingestion-design.md` | O02 |
| `docs/operations/variable-library-environment-binding.md` | D02 |

**Paths changed after plan was written.** Images are now under **nested screenshot folders**, e.g. from `docs/guides/...` to `../assets/screenshots/core/c01-control-metadata.png`. D01/D02 paths: `../assets/diagrams/d01-control-audit-er.svg` and `../assets/diagrams/d02-environment-binding.svg` when referencing from `docs/guides` or `docs/operations`. From repository-root README, use `docs/assets/...`. Verify all relative Markdown links after insertion.

**README:** Keep current README content/navigation. Add at most **two high-value images** after review: first choice **O01 end-to-end trace** and **C15 Operations Monitoring**; if O01 is not good enough, replace it with **C03 master orchestration**. README acts as landing page; deeper guides hold technical detail.

**Technical QA after integration:** confirm pipeline/activity names from checked-in definitions, paths, environment claims, execution semantics, AUTO-vs-zero language, reproducible performance claims, privacy and run provenance, screenshot captions, readability, and no false impression that UAT/PROD has been tested. Current Markdown had **no references to C/P/CX/PX or D01/D02** when filenames were reorganized, so the path relocation did not break already-inserted screenshot links.

## 8. Current work plan — what to do next and in what order

### Phase A — Filename-first curation (next task)

- Start from `EVIDENCE_INVENTORY.csv` and current GitHub tree, **not** from visual inspection of 58 images at once.
- Evaluate one group at a time, likely **S1**, then S2→S5, performance S8, optional O01/O02/O05, and final direct C/P.
- For each group, map intended claims to its files; choose likely publication images; identify necessary composites and crops; mark `PUBLISH_DIRECT`, `COMPOSITE_SOURCE`, `ARCHIVE_ONLY`, or `SKIP` only after enough evidence to justify it.
- Agree exact naming for composite outputs and whether to use one panel or several separate images. The user explicitly said **C04, C07, P01** should use several screenshots instead of an obligatory single merged image.
- Keep any detailed per-image review *scoped to the current batch*. Use user-supplied status/observations rather than inferring test results from filenames.

### Phase B — Composite production and measured comparison

- Build C10–C13, O01/O02/O05 selectively from real constituent screenshots. Composite labeling must be explicit. Preserve traceability to original images and evidence IDs; do not cosmetically alter pass/fail/results or invented before/after timestamps.
- Build P05 from **real, comparable completed benchmark outputs**; if insufficient, report limitation and skip comparison instead of manufacturing numbers.
- D01/D02 do not need further conceptual changes.

### Phase C — Markdown integration + QA

- Insert curated diagrams/screenshots in mapped guides **sparingly**, write evidence-based captions, and check relative paths.
- Add selected 1–2 images in README, no full rewrite.
- Validate markdown links/rendering; verify technical statements against current code and collected run evidence; make a commit. Update handoff if important decisions change.

### Living handoff update protocol

- After each completed evidence batch, update `EVIDENCE_INVENTORY.csv` only for assets actually reviewed. A file in Git is **not** equivalent to a visually verified or publish-ready screenshot.
- Update `PROJECT_HANDOFF.md` with verified milestone status, remaining actions and relevant commit references. Update `CONTINUATION_PROMPT.md` if the next task changes. Use `SCREENSHOT_IMPLEMENTATION_PLAN.md` for batch scope, composite rules, Markdown placement and acceptance criteria.
- All `.project-handoff/` files are public. Do not add secrets, credentials, unpublished client artifacts, private run/batch identifiers or environment-specific GUIDs.
- After portfolio QA is complete, remove `.project-handoff/` in a cleanup commit after preserving necessary permanent knowledge in canonical documentation. Deletion does not purge earlier public commits.

### Phase D — final handoff or finish

- When moving conversations, refresh the live GitHub handoff with current milestone, reviewed inventory, completed composites, actual commit and next exact work item. Do not call unfinished images complete.

## 9. Things **not** to redo or quietly change

- No more Variable Library UI screenshot hunt; intentionally excluded.
- Do not reopen D01 title formatting or D02 Power BI/UAT/PROD styling debates absent an evidenced bug.
- Do not invent fake DEV/UAT/PROD deployments for a portfolio screenshot.
- Do not delete exact-equal S2 or S5 watermark before/after evidence just because the file hashes match—unchanged checkpoint is expected in those scenarios.
- Do not transform real engineering evidence with artistic image generation. For architecture diagrams, editable SVG; for evidence composites, use actual screenshots; for P05, measured numbers only.
- Do not assume raw binary screenshot images were reviewed simply because GitHub has them.
- Do not create redundant new Technical Guides if existing canonical guides cover the topic.
- Do not treat planned optional O03/O04 as required; user explicitly dropped them.
- This temporary sanitized handoff was explicitly authorized for the public repository. Never commit detailed private run logs, private environment IDs or secrets. A later delete does not remove prior Git history.

## 10. Key authoritative repository references

- `README.md`
- `docs/architecture/framework-overview.md`
- `docs/architecture/generic-incremental-watermark.md`
- `docs/architecture/database-copy-performance.md`
- `docs/architecture/file-ingestion-design.md`
- `docs/guides/control-plane.md`
- `docs/guides/pipeline-orchestration.md`
- `docs/guides/sql-server-database-ingestion.md`
- `docs/guides/sftp-file-ingestion.md`
- `docs/operations/retry-rerun-backfill.md`
- `docs/operations/run-request-examples.md`
- `docs/operations/monitoring-report.md`
- `docs/operations/variable-library-environment-binding.md`
- `docs/operations/environment-rebuild.md`
- `scripts/control/02_create_control_procedures.sql`
- `scripts/monitoring/01_create_monitoring_views.sql`
- `fabric/` tracked Fabric items
- `docs/assets/diagrams/` finalized SVGs
- `docs/assets/screenshots/` filename-sorted evidence

## 11. Provenance and confidence

- **Checked against GitHub repository on 2026-10-24:** branch head/commit, actual asset paths/counts, README and key technical guides, D01/D02 existence, monitoring and performance guardrails, current environment runbook.
- **User-provided decisions:** exact C/P/O target filenames and `SKIP`/`COMPOSITE`/`multiple screenshots` notes; D01/D02 visual preferences; request for minimum-effort filename-first batch curation; temporary public-repository handoff strategy.
- **Not established by this handoff:** visual content or privacy review of each PNG, completed review of all 26 candidates, availability of original Run IDs or Test SHA for every scenario, values for final P05 comparison, existence of planned C10–C13/P05/O01/O02/O05 composites, UAT/PROD deployment success, full Activator alert delivery.

**Next action when continuing:** Start **Evidence Curation Batch 1**, choose a small group and review filenames plus the user's annotation first; request/inspect actual image content only where necessary to decide which particular screenshot(s) can substantiate the intended claim. No redesign, no mass visual scan.