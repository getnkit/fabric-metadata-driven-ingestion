# Orchestrator Failure Alerting

## Decision

Failure notification is an operational layer around the ingestion framework,
not another branch inside every child pipeline.

Monitor only the supported external entry point:

```text
pl_ingest_orchestrator
  Failed
    -> operator notification
```

Do not add Outlook/Teams notification activities to each failure path.

Source-scoped schedules invoke the **same** `pl_ingest_orchestrator` item
with different `p_source_system` values. Its monitoring/Activator rule still
monitors that pipeline item, but its individual runs and Batch IDs are distinct.
A FAILED master run means that at least one config in **that run's scope**
failed, not that all configured source systems failed. All Active without a
scope remains a global batch and may fail if any included source fails.

## Fabric setup

Because scheduling is not part of the current project scope, use a Fabric
Activator rule on pipeline job events rather than schedule-only failure
notifications.

Configure the rule in the Fabric workspace after syncing the pipeline from Git:

1. Create or open an Activator item.
2. Add Fabric job events as the source.
3. Select `pl_ingest_orchestrator`.
4. Trigger only when the pipeline job status is Failed.
5. Send the notification to the chosen email or Microsoft Teams destination.
6. Enable the rule.

The recipient/channel is environment-specific and is intentionally not stored
in this repository.

## Acceptance

During the negative runtime acceptance test, verify all three outcomes together:

```text
pl_ingest_orchestrator = FAILED
expected object-level audit = FAILED when an object/config was resolved
operator failure notification = received
```

Successful and SKIPPED runs do not need notifications in the current scope.
