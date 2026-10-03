# Fabric Data Factory Limits and Framework Guardrails

## Purpose

This project is intended to represent a production-minded metadata-driven ingestion framework. Platform limits that can affect core orchestration are treated as architecture inputs rather than left as hidden runtime surprises.

Limits change over time. Recheck the Microsoft Fabric Data Factory limitations page before materially increasing scale.

Official references:

- https://learn.microsoft.com/en-us/fabric/data-factory/data-factory-limitations
- https://learn.microsoft.com/en-us/fabric/data-factory/lookup-activity
- https://learn.microsoft.com/en-us/azure/data-factory/control-flow-for-each-activity
- https://learn.microsoft.com/en-us/azure/data-factory/control-flow-get-metadata-activity

## Guardrail summary

| Area | Current documented limit / constraint | Framework handling |
|---|---|---|
| Lookup rows | 5,000 rows | Orchestrator metadata enumeration is paged. Default page size is 1,000 and requests are rejected above 5,000. |
| Lookup output | 4 MB | Each config page returns only `ingestion_config_id`, keeping payload small. Other active lookups are single-config or scalar queries. |
| Activities per pipeline | 120 including inner container activities | Keep connector/routing responsibilities separated into bounded child pipelines and review pipeline size when extending the framework. |
| Pipeline parameters | 50 | Current pipelines remain well below the limit; keep parameter contracts bounded when extending adapters. |
| ForEach items | 100,000 | Config page worker receives at most 5,000 items and defaults to 1,000. |
| ForEach parallelism | default 20, maximum 50 | `fe_ingestion_configs` intentionally uses `batchCount = 3` to bound downstream concurrency. |
| Nested ForEach / Until pattern | ADF orchestration guidance does not allow direct ForEach nesting in another ForEach or Until | Two-level pipeline pattern is used when paging is required. |
| Expression length | 8,192 characters | Keep dynamic expressions focused and review long generated expressions before release. |
| Activity-run payload | 896 KB | Pipelines pass metadata, IDs, paths, and connection references rather than row-level datasets between activities. |
| Concurrent Lookup / GetMetadata / Delete per workspace | 100 | Orchestrator pagination is sequential across pages and inner config parallelism is bounded. |
| Maximum queued runs per pipeline | 100 | `pl_ingest_orchestrator` keeps `concurrency = 1`; trigger cadence should be managed operationally. |
| Activity timeout | 24 hours in the current pipeline resource-limit table | Current project activity policies remain below the platform ceiling. |

## Lookup pagination design

The original single-lookup pattern was:

```text
lkp_active_configs
  -> fe_ingestion_configs
```

That pattern silently truncates once Lookup returns more than 5,000 rows.

The production-safe pattern is:

```text
pl_ingest_orchestrator
  -> lkp_config_pagination_info
  -> fe_config_pages (sequential)
       -> inv_ingest_config_page_dispatcher

pl_ingest_config_page_dispatcher
  -> lkp_config_page
       OFFSET page_index * page_size
       FETCH NEXT page_size
  -> fe_ingestion_configs
       batchCount = 3
       -> inv_ingest_object_controller
```

Default:

```text
p_config_page_size = 1000
```

Allowed:

```text
1 <= p_config_page_size <= 5000
```

The smaller default leaves headroom below both the row-count and output-size limits while remaining efficient for normal metadata volumes.

For acceptance testing, the page size can temporarily be set to a small value such as 2 so the multi-page path can be exercised without seeding thousands of configurations.

## Other activity-specific awareness

### ForEach

The framework avoids shared pipeline-variable mutation inside parallel ForEach loops. Variables are pipeline-scoped rather than iteration-scoped, so stateful per-item work belongs in the invoked child pipeline or should run sequentially.

The orchestrator page loop is sequential to avoid multiplying concurrency by page count. Parallelism is applied only inside the bounded config page worker.

### Get Metadata

The active ingestion framework no longer depends on Get Metadata for recursive SFTP discovery. The SFTP Copy connector performs recursive discovery natively.

The equivalent Azure Data Factory orchestration documentation caps returned Get Metadata payload at 4 MB. The retained legacy pipeline may still contain Get Metadata, but it is intentionally excluded from active architecture refactoring and is not used for scalable source-tree enumeration.

### Copy

Copy remains the preferred primitive for connector-native transport:

```text
DATABASE -> Bronze
SFTP -> Landing
```

Notebook is used only when Spark/Delta processing adds value, such as recursive Landing parsing, technical metadata enrichment, or compensating Delta cleanup.

For SFTP incremental ingestion, Microsoft notes that Last Modified filtering can affect data-movement performance when a source contains very large numbers of files. This is a scale consideration rather than a hard correctness limit. If that becomes material, prefer source-side partitioning or a manifest/receipt-state pattern instead of rebuilding recursive traversal in pipeline control flow.
