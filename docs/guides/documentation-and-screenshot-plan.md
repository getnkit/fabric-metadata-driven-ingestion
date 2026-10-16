# Documentation and Screenshot Plan

This is a working plan for turning the educational reading path into an illustrated engineering reference. It is not runtime evidence, and none of the proposed screenshots should be described as captured until the corresponding Fabric DEV run has been inspected.

## Who the documentation is for

The primary reader knows SQL and basic data integration but may be new to Fabric Data Factory. A more experienced reader should be able to follow links from the explanation to the exact Pipeline JSON, SQL procedure, or Notebook implementation.

The writing goal is to make a real implementation understandable. It is not to sell a framework, retell a resume, or present every activity property without context.

Use three kinds of material:

1. **Explanation:** the problem, the design decision, and why the trade-off was chosen.
2. **Guided walkthrough:** a specific input, the path it follows, and how the reader can verify the result.
3. **Reference:** exact fields, parameter contracts, expressions, and failure semantics in canonical files.

Link to existing architecture and operations docs where they already answer a question. Do not paste the same specification into a second page.

## Writing guidelines

- Start sections with a real engineering question or a specific task. Avoid long introductions that restate the heading.
- Prefer active voice and concrete subjects: "The File Router checks `file_format`" rather than "Validation is performed."
- Explain the decision after the observable behavior: "The file goes to Landing first so the original delivery remains available for inspection."
- Use exact Fabric item, activity, field, and parameter names from the checked-in artifacts. Do not invent expressions to make an example simpler.
- Distinguish source code, expected runtime behavior, and results observed during a run. Add an observation date or run reference to claims based on measurements.
- Avoid exaggerated wording such as "seamless," "robust," "enterprise-grade," "revolutionary," and "production-proven" unless there is a precise and defensible claim.
- Avoid decorative transitions and repetitive wrap-up paragraphs. Prefer one useful caveat over three generic caution paragraphs.
- Use ordinary punctuation. Do not use double hyphens as a substitute for punctuation, and do not rely on long strings of em dashes.
- A procedure should state where to work, the action to take, and the expected result. Use a numbered list for ordered actions.
- Keep screenshots close to the behavior they demonstrate. Every important screenshot needs alt text, an informative caption, and a textual explanation that still works without the image.
- Keep a deliberate distinction between a **conceptual diagram** and an **actual product screenshot**. Never generate a fake Fabric UI screenshot and present it as a verified run.

### Example of the intended voice

Less useful:

> This powerful and scalable framework seamlessly enables efficient ingestion by leveraging dynamic metadata, providing flexibility and reliability across a wide variety of enterprise scenarios.

Better:

> The orchestrator reads active configurations from `control.ingestion_config`. Each row specifies the source, load strategy, and Bronze target. The framework uses that metadata to dispatch the object without creating another master pipeline.

The second version tells readers what to look for in the repository and can be checked against an artifact.

## Diagram strategy

Use **Mermaid by default** for diagrams that explain executable logic, routing, state, and dependencies. Keep the source embedded in Markdown so changes can be reviewed with the surrounding implementation. Prefer two focused diagrams over one wall of Pipeline activities.

| Level | What it answers | Recommended format |
| --- | --- | --- |
| Framework overview | Which major subsystems exchange metadata and data? | Concise Mermaid; optional carefully reviewed SVG for the README's published overview |
| Pipeline-level flow | How do Orchestrator, Paginator, Dispatcher, Controller, and Routers interact? | Mermaid showing pipeline boundaries and the meaningful decisions |
| Activity-level flow | Why does a particular INCREMENTAL, SKIPPED, or recovery branch run? | Mermaid extracted from the actual Pipeline JSON; focus on decision activities and critical failure paths |

The first activity-level examples are in [SQL Server Database Ingestion](sql-server-database-ingestion.md). Avoid an all-activities, all-pipelines poster. If detail would make an individual diagram unreadable, link the canonical Pipeline JSON instead.

A conceptual Mermaid or SVG diagram is **not runtime evidence**. Separate it from Fabric Monitor screenshots that show real activities and outcomes. Do not add screenshot-style activity icons or synthetic Fabric canvases just to make a diagram look like a runtime trace.

## Screenshots to capture

Capture only views that answer a question the walkthrough has raised. Use the same sample source and a consistent run identity across adjacent screenshots where possible.

| Figure | What the reader should see | Where it belongs |
| --- | --- | --- |
| F01 | A compact architecture diagram naming the Control Plane, Dispatcher, adapters, Landing, Bronze, and Audit | README / architecture overview |
| F02 | SQL results showing `ECOMMERCE` and `LOGISTICS_VENDOR` configuration rows, including FULL and INCREMENTAL | [Control Plane](control-plane.md) and SFTP ingestion guide |
| F03 | The Orchestrator parameters with `p_run_requests=[]` and `p_source_system=LOGISTICS_VENDOR` | SFTP ingestion guide, step 2 |
| F04 | Actual Orchestrator or child-pipeline run graph, with the dispatch route visible | SFTP ingestion guide, step 2 |
| F05 | FILE Router properties showing the supported-format gate and route selection | FILE adapter reference |
| F06 | SFTP FULL Binary Copy details and the resulting execution-scoped Landing folder | SFTP ingestion guide, step 3 |
| F07 | Notebook execution output and Bronze table columns including `_batch_id` and `_pipeline_run_id` | SFTP ingestion guide, step 3 or 5 |
| F08 | SQL audit row for the same object execution and batch | SFTP ingestion guide, step 5 |
| F09 | Before/after watermark values for a successful FILE INCREMENTAL run with new remote files | Incremental watermark reference |
| F10 | A no-new-files FILE INCREMENTAL `SKIPPED` run plus unchanged checkpoint | Incremental watermark reference |
| F11 | Explicit BACKFILL request, audit bounds, and unchanged operational checkpoint | Backfill / reliability reference |
| F12 | Power BI Operations report with source summary and Object Execution History | Monitoring guide |
| F13 | `lkp_ingestion_config` Lookup settings and selected Object Controller route | [Pipeline Orchestration](pipeline-orchestration.md) |
| F14 | SQL Server FULL and INCREMENTAL configuration rows in `control.ingestion_config` | [SQL Server Database Ingestion](sql-server-database-ingestion.md) |
| F15 | `lkp_current_watermark`, `lkp_source_upper_bound`, and resulting incremental Copy | SQL Server database guide |
| F16 | SQL Server audit row and watermark before/after for the same actual run | SQL Server database guide |

Start with **F01, F02, F03, F04, F13** to explain the architecture, metadata, and orchestration. Then capture **F06, F07, F08** for the SFTP execution. Add the remaining figures only when their scenario is reproducible.

For F01, keep the canonical Mermaid technical view; the existing README SVG is an optional conceptual overview, not a synthetic Fabric product screenshot. For complex canvases, use a focused screenshot plus a simplified diagram instead of shrinking the entire activity graph until labels are unreadable.

The [benchmark evidence plan](../benchmarks/evidence-and-test-plan.md) tracks measured performance experiments separately. Do not mix benchmark screenshots with the core educational walkthrough unless they clarify a particular Copy setting.

## DEV test scenarios

These are proposed capture sessions. They have not been executed by this document.

| Scenario | Setup and action | Expected evidence | Important constraint |
| --- | --- | --- | --- |
| S01: inspect metadata | Query the two Logistics configuration rows | Source options, FULL versus INCREMENTAL, target paths | Read-only, no Fabric run needed |
| S02: capture a normal run | Run `pl_ingest_orchestrator` with blank requests and source system `LOGISTICS_VENDOR` | Dispatch path, Landing, Bronze, terminal audit | Outcomes depend on current files and checkpoints |
| S03: no new movement files | Re-run without uploading another movement file | FILE INCREMENTAL `SKIPPED` and unchanged watermark | FULL snapshot may append another batch in the same scoped run |
| S04: new movement file | Generate one sample movement CSV, upload to the documented SFTP location, and run a single explicit REGULAR request for the actual `inventory_movement` config ID | Remote mtime boundary, SUCCESS if matching files are processed, changed checkpoint | Use the config ID returned by SQL; do not assume a fixed ID |
| S05: historical BACKFILL | Choose a known historical remote-file window, run explicit BACKFILL for the incremental config, and inspect audit plus checkpoint before/after | Requested bounds and unchanged operational checkpoint | Verify the files are still available; don't infer SUCCESS in advance |
| S06: invalid scope | Supply both a nonblank `p_source_system` and a nonempty `p_run_requests` | `AMBIGUOUS_RUN_SCOPE` before object dispatch | Expect no object-level audit for this master-level rejection |
| S07: recovery evidence | Reuse an existing verified failed execution or a deliberately isolated, reviewed DEV fault-injection test | Compensation path and audit correlation | Do not damage an active workspace merely to produce a screenshot |
| S08: monitoring | Open the official Power BI report after a verified audit | Latest source summary and object history | This is terminal object audit, not a live master-run status view |
| S09: SQL Server FULL | Select the actual `catalog.product_categories` config ID and run it through the master | Query-mode Copy, new Bronze batch, terminal audit | Successful FULL appends and does not create a watermark |
| S10: SQL Server INCREMENTAL | Select the actual `crm.customers` config ID and capture state before/after a REGULAR run | Source-derived HIGH, Copy branch when the boundary advances, finalized checkpoint | No-new-data may SKIP; only claim a watermark change if observed |

For an explicit single-object REGULAR request use the JSON shape below after looking up the current `ingestion_config_id`:

```json
[
  {
    "config_id": 8,
    "run_type": "REGULAR"
  }
]
```

The numeric ID above illustrates the original fresh DEV seed order. **Replace it with the actual ID in the environment you are using.** Leave `p_source_system` blank when passing an explicit request array. For a historical BACKFILL add both required bounds using source-appropriate timestamp values.

Before any session, record the UTC start time, current committed watermark, source file names and Last Modified values, and selected parameters. After the run, record its master Run ID, Batch ID, object Run IDs, audit statuses, and target table. Without these identifiers it may be difficult to prove that screenshots from different screens belong to the same execution.

## Capture and acceptance checklist

1. Prepare a dedicated DEV capture session with known sample files. Avoid changing orchestration logic only to make a screenshot attractive.
2. Select one scenario and record the expected assertion before executing it.
3. Run the scenario in Fabric or query the Control SQL Database as appropriate.
4. Verify observed values in the UI and the Control/Audit tables. A green pipeline canvas alone does not prove the expected watermark or Bronze outcome.
5. Capture the relevant UI at readable zoom. Crop away browser chrome and unrelated workspace navigation when it does not help the explanation.
6. Use stable filenames such as `docs/assets/sftp/02-orchestrator-scope.png` or `docs/assets/sftp/06-audit-outcome.png`. The numbers track the narrative, not global screenshot IDs.
7. Write alt text describing the important UI state and a caption explaining what it proves. Keep the run's date and evidence references in a short adjacent note.
8. Verify images against the current Pipeline definitions before linking them into the walkthrough. If the UI or implementation changes, either refresh the screenshot or clearly label the captured version.
9. Do not create an empty image file, placeholder link, fabricated run ID, or inferred runtime metric. Leave a textual explanation in place until real evidence is available.

A screenshot should show only enough context to support its claim. If both a parameter value and a final Audit row matter, prefer two readable screenshots with one explanation connecting them.

## Writing and review workflow

For each new walkthrough chapter:

1. **Ground:** read the corresponding SQL, Pipeline JSON, Notebook, and existing docs.
2. **Outline:** identify one reader question and the minimum steps needed to answer it.
3. **Draft:** explain the observable data path first, then important design choices and failure conditions.
4. **Cross-check:** confirm every activity name, parameter, field, expression and link against source.
5. **Reader test:** ask whether someone unfamiliar with the implementation could follow the chapter and reproduce its checks.
6. **Visual pass:** add only captured screenshots that improve comprehension; check captions and alt text.
7. **Editorial pass:** remove repetition, generic claims, double hyphens and ornamental transitions.

This loosely follows the collaborative drafting and reader-testing method described by the [Doc Co-Authoring skill](https://github.com/anthropics/skills/tree/main/skills/doc-coauthoring). For wording, procedure formatting and screenshot placement, use the [Microsoft Writing Style Guide](https://learn.microsoft.com/en-us/style-guide), [procedure checklist](https://learn.microsoft.com/en-us/style-guide/checklists/procedures-and-instructions-checklist) and [responsive content guidance](https://learn.microsoft.com/en-us/style-guide/responsive-content). These are editorial references, not a dependency or a requirement to install another agent.

## Proposed chapter order

1. Metadata and Control Plane: start with the [Control Plane guide](control-plane.md) and a real configuration query.
2. Orchestrator and dispatch: use the [Pipeline Orchestration guide](pipeline-orchestration.md) to show all-active, source-scoped and explicit requests.
3. FILE adapter: use the two Logistics feeds in the [SFTP File Ingestion guide](sftp-file-ingestion.md).
4. DATABASE adapter: use the [SQL Server Database Ingestion guide](sql-server-database-ingestion.md) to show Query-mode Copy, FULL/INCREMENTAL, and Copy settings.
5. Watermark and BACKFILL: demonstrate state invariants with before/after verification.
6. Finalization and recovery: trace the finalizer and compensating cleanup with verified evidence.
7. Audit and operations: connect SQL views to Power BI and explain observability gaps.
8. Rebuild: link the existing fresh DEV runbook rather than restating deployment instructions.

Do not create all eight chapters at once. Finish one narrow, source-grounded chapter, test it with a reader, then expand the next area.
