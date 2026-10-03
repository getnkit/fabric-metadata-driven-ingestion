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
