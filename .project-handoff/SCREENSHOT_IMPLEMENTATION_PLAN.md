# Screenshot Implementation Plan — Codex Work Order

> **Temporary working document**, prepared 2026-10-25 (Asia/Bangkok) for the public personal portfolio repository `getnkit/fabric-metadata-driven-pipelines`. Do not treat this as published engineering documentation. Read current HEAD and the three companion files in `.project-handoff/` before starting.

## 1. Objective and source of truth

Finish **Evidence Curation → Composite Construction → Markdown Integration → README/QA**, preserving actual run results and architecture. Quality and traceability outrank a one-day deadline, but do not expand scope or redesign completed implementation.

Source of truth: live `fabric/`, `scripts/`, `docs/`, original PNG/SVG Git blobs, and `.project-handoff/EVIDENCE_INVENTORY.csv`. The working inventory has **58 screenshots and 2 finalized SVG diagrams**. A file being present does **not** mean it was visually verified, accepted or integrated into Markdown.

**Roles:** Codex performs repeatable repo edits and deterministic image composition; ChatGPT scopes and technically reviews; the owner approves publish/skip decisions. Run Codex on a feature branch (e.g. `docs/evidence-curation`) and commit small batches rather than one sweeping change. Update this handoff after each completed batch.

## 2. Preserve existing asset taxonomy

- `docs/assets/screenshots/core/` — 10 direct C candidates.
- `docs/assets/screenshots/performance/` — P02, P03, P04.
- `docs/assets/screenshots/performance/source-config/` — three PX-S8 benchmark configs.
- `docs/assets/screenshots/supporting/s1-orchestration/` — 22 execution/routing details for C04/C07.
- `docs/assets/screenshots/supporting/s2-no-new-data/` — four C10 inputs.
- `docs/assets/screenshots/supporting/s3-sql-incremental/` — three C11 inputs.
- `docs/assets/screenshots/supporting/s4-sftp-incremental/` — four C12 inputs.
- `docs/assets/screenshots/supporting/s5-backfill/` — three C13 inputs.
- `docs/assets/screenshots/supporting/optional/o01-end-to-end/` — one O01 source.
- `docs/assets/screenshots/supporting/optional/o02-file-row-count/` — two O02 sources.
- `docs/assets/screenshots/supporting/optional/o05-source-scope/` — three O05 sources.
- `docs/assets/diagrams/d01-control-audit-er.svg` and `d02-environment-binding.svg` — finalized; do not redesign.

**No wholesale rename/move:** 58 PNG files have already been grouped. Keep original CX/PX evidence unchanged and separate from generated composites. Suggested derived output location: `docs/assets/screenshots/composites/`; create it only when the first composite is accepted. Update links and inventory together if paths change.

## 3. Work sequence and checkpoints

**Stage 0 — Preflight:** check Git HEAD/clean working tree, read handoff/inventory, inventory all 60 asset paths, verify they exist and filenames match. Check image integrity and approximate size/resolution. Generate per-scenario **contact sheets** for review; do not automatically commit these intermediate contact sheets. Check for secrets, tokens, connection strings, personally identifying or client information before publishing any newly assembled image. Prepare a concise evidence table with `candidate | original inputs | intended claim | proposed placement | gaps`.

**Stage 1 — Batch curation:** work in the A–H batches below. Review filenames and thumbnails first; only open full-size images when necessary to support a technical claim. For each candidate decide `DIRECT | MULTI_IMAGE | COMPOSITE | ARCHIVE | SKIP`. Source filenames and user annotations govern initial candidate mapping; actual run evidence governs acceptance. Do not use an image just to satisfy a count.

| Batch | Screenshots / proposed work | Intended Markdown |
| --- | --- | --- |
| **A: Control Plane** | C01 `core/c01-control-metadata.png`, C02 `core/c02-logical-connections.png`, D01. Direct images + finalized model; no composite. | `docs/guides/control-plane.md` |
| **B: Orchestration** | C03 `core/c03-master-orchestration.png`, C04/C07 selected panels from 22 `supporting/s1-orchestration/` images; O01 from `supporting/optional/o01-end-to-end/` only if true end-to-end run correlation is supported. **Use multiple readable panels** for C04/C07, not an unreadable huge stitched flow. | `docs/guides/pipeline-orchestration.md`; optional O01 in `docs/architecture/framework-overview.md` and README |
| **C: SQL Server** | C05 `core/c05-sql-server-copy-execution.png`, C06 `core/c06-sql-bronze-lineage.png`; C11 composite from S3 audit-success + watermark-before/after. Show successful REGULAR INCREMENTAL and actual checkpoint advancement, not invented bounds. | `docs/guides/sql-server-database-ingestion.md` |
| **D: SFTP** | C07 panels from S1; C08 `core/c08-sftp-landing.png`, C09 `core/c09-sftp-bronze-lineage.png`; C12 composite from four S4 source images; O02 optional using two file/row-count images. Distinguish Binary Landing file movement vs Notebook parsing/Bronze rows. | `docs/guides/sftp-file-ingestion.md`; `docs/architecture/file-ingestion-design.md` if O02 supported |
| **E: Incremental, Backfill, Scope** | C10 composite from S2 (4 images); C13 from S5 (3); C14 `core/c14-ambiguous-run-scope.png`; optional O05 from three source-scope images. C10: SKIPPED + no append + unchanged watermark. C13: BACKFILL can succeed without advancing operational checkpoint. | `docs/architecture/generic-incremental-watermark.md`, `docs/operations/retry-rerun-backfill.md`, `docs/operations/run-request-examples.md` |
| **F: Copy Performance** | P01 **multiple** PX-S8 config screenshots; P02 `performance/p02-query-none.png`, P03 `performance/p03-query-dynamic-range-auto.png`, P04 `performance/p04-query-dynamic-range-tuned.png`; P05 only if comparable completed metrics exist. | `docs/architecture/database-copy-performance.md` |
| **G: Monitoring** | C15 `core/c15-operations-report.png` and C16 `core/c16-operations-filter.png`. Monitoring report reflects terminal object audits, **not live master-run state**. | `docs/operations/monitoring-report.md`; optional README |
| **H: Environment Binding** | D02 finalized `docs/assets/diagrams/d02-environment-binding.svg`; no Variable Library UI screenshot required. UAT/PROD are Design only, not tested deployments. | `docs/operations/variable-library-environment-binding.md` |

O03 and O04 were **explicitly excluded** from final publication. Do not resurrect them merely to fill coverage.

## 4. Composite rules (Codex as builder; humans as reviewers)

- Use **only real source screenshots**, unmodified original data. Codex may crop irrelevant surroundings, scale, layout panels, add neutral borders, numbered section headings and concise evidence-based labels. Never fabricate screenshots, values, statuses, run IDs, timestamps, query metrics or SQL results.
- Preserve original CX/ PX screenshots and record a derived manifest: `candidate | input paths | output | intended claim | run correlation checked? | review state`. Store only public-safe facts. Do not put an environment-specific private Run ID/Batch ID log in this public folder.
- **C10:** `cx-s2-skipped-audit.png`, `cx-s2-no-bronze-append.png`, `cx-s2-watermark-before.png`, `cx-s2-watermark-after.png`. State does not advance for SKIPPED. The before/after files have identical Git blob hashes: consistent with unchanged checkpoint, **not proof of independent before/after captures**.
- **C11:** `cx-s3-watermark-before.png`, `cx-s3-audit-success.png`, `cx-s3-watermark-after.png`. Check the actual timestamp values and recorded audit before claiming advance.
- **C12:** S4 `watermark-before`, `bronze-new-file-lineage`, `audit-success`, `watermark-after`. Claim only observed new-file incremental success.
- **C13:** `cx-s5-watermark-before.png`, `cx-s5-audit-backfill.png`, `cx-s5-watermark-after.png`. The before/after blobs are identical; BACKFILL must not advance operational watermark. Do not imply independently captured state if not supported.
- **O01:** only `cx-o01-audit.png` is present in the optional folder, so this **cannot independently prove a complete end-to-end execution trace**. Use other verified, correlated screenshots or downgrade to an audit figure. Do not imply unrelated screenshots represent one run.
- **O02:** Binary Copy vs Notebook parsing may show file-count vs row-count differences; verify source semantics and avoid conflating metrics.
- **O05:** source-scope input + paginator selection + batch audit must correspond to demonstrably related execution(s). Do not infer correlation from similar labels alone.
- **P05:** requires defensible, *completed*, comparable DEV measurements with labels/units for source physical layout, Copy partition strategy, requested/actual parallel copies, duration, throughput, data read/rows, used DIUs, Fabric capacity, source hardware pressure, target pre-run state. If data are incomplete, mark **not supported yet** rather than inventing chart data. **Omitted `parallelCopies` (AUTO) ≠ explicit `parallelCopies = 0`**; the repo's separate PoC shows different observed parallelism, not a completed comparable AUTO speedup.

Readable GitHub-width panels matter more than squeezing every capture into one PNG. If panels require illegible font sizes, publish multiple screenshots with captions instead.

## 5. Markdown integration — after each batch passes review

- Apply approved figures to **existing guides** rather than creating redundant documents. Integrate one accepted batch at a time; don't wait for all 58 screenshots to be individually reviewed before starting documentation.
- Root README image path: `docs/assets/...`. Paths from `docs/guides/`, `docs/architecture/` and `docs/operations/`: `../assets/...`. Old flat screenshot links are wrong after file grouping; always use categorized paths.
- Captions say **what the evidence demonstrates** and how far the claim goes; distinguish a conceptual SVG from observed execution. Never imply UAT/PROD are deployed, Power BI captures pre-audit failures, or Bronze ingestion has global exactly-once business-record semantics.
- Keep existing README navigation and overview; **add at most two standout figures** (tentatively O01 if validated, plus C15; use C03 if O01 cannot be supported). Do not rewrite README in bulk.
- Use D01 in Control Plane guide; D02 in Variable Library binding runbook. Preserve SVG as editable source.

## 6. QA, update protocol and definition of done

After each batch: verify exact PNG inputs against source blobs; visually inspect outputs at readable scale; inspect captions against source code/runbook and genuine execution; confirm paths resolve; review diff; obtain project-owner approval; then update the CSV (`visual_review`, `publication_decision`, notes) **only for genuinely processed entries** and record new derived files in a manifest. Update `PROJECT_HANDOFF.md` progress and `CONTINUATION_PROMPT.md` only where next steps have changed.

Final gate: all selected direct and derived evidence is accurate, traceable and privacy-reviewed; guide image links render; comparisons use actual numbers; current pipeline/activity names match source; README remains concise; owner signs off; no essential outstanding contradictions. The goal is **adequate correct coverage**, not arbitrary inclusion of all 26 planned candidate IDs. Remove temporary `.project-handoff/` by cleanup commit after final portfolio QA; public Git history still retains earlier snapshots.

## 7. First Codex assignment (Batch A, gated)

**Prompt to Codex:** Read the live repo and all four files in `.project-handoff/`. Confirm current HEAD, asset paths and a clean working tree. Focus on **C01, C02 and D01 only**. Inspect their content and `docs/guides/control-plane.md`; propose exact figure placements and evidence-based captions. Explain any unreadable or mismatched images. **Do not yet edit Markdown, create composites, or commit without review of your proposal**. After approval, make one small branch commit to insert accepted assets, validate relative paths, and update evidence state. Report the diff and review checklist. Then proceed to Batch B only after review.

Keep each task narrowly scoped, maintain the status files, and avoid claiming a file was visually verified until someone actually checked its content.
