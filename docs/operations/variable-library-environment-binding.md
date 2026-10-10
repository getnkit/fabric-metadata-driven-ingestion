# Fabric Variable Library — Runtime Connection Management

## Scope and decision

The Personal metadata-driven ingestion framework uses one Fabric Variable Library:
`vl_ingestion_connections` (same workspace as `pl_ingest_orchestrator`).

It exposes **four String variables** holding environment-specific GUIDs:

| Variable | Consumer | Value required per environment |
| --- | --- | --- |
| `ingestion_control_connection_id` | Control SQL Lookup / Stored Procedure | Fabric SQL Database **Connection** GUID |
| `ingestion_control_item_id` | Control SQL Lookup / Stored Procedure | `sqldb_ingestion_control` **SQL Database item** GUID |
| `pipeline_invoke_connection_id` | Invoke Pipeline | Fabric **Invoke Pipeline Connection** GUID |
| `notebook_execution_connection_id` | Notebook activities | Fabric **Notebook execution Connection** GUID |

A Connection GUID is **not** a workspace ID or SQL Database item ID. Record each
one from the correct DEV/UAT/PROD workspace and connection, and verify that the
workspace user has permission to use it. Do not paste display names instead of
GUIDs. The version-controlled Library ships with four **empty String values**
so that a DEV-only GUID is not silently deployed as a PROD default. Do not
commit passwords, tokens, or other credentials.

Each of the eleven framework pipelines declares only the library variables it
consumes under `properties.libraryVariables` and resolves them locally with
`@pipeline().libraryVariables.<name>`. This deliberately **does not** introduce
pipeline parameter forwarding for runtime connection IDs.

The supported **external entry point** remains `pl_ingest_orchestrator`. Its
`if_required_connections_provided` guard rejects any missing/empty value with
`MISSING_RUNTIME_BINDING` before object dispatch. A direct child pipeline run
is outside the supported operational flow; the child nevertheless needs its
own active Library bindings to execute.

## What is and is not parameterized

- Control SQL activity `externalReferences.connection` uses
  `@pipeline().libraryVariables.ingestion_control_connection_id`.
- Control SQL activity `connectionSettings.properties.typeProperties.artifactId`
  (including nested Lookup dataset connections) uses
  `@pipeline().libraryVariables.ingestion_control_item_id`.
- Invoke Pipeline `externalReferences.connection` uses
  `@pipeline().libraryVariables.pipeline_invoke_connection_id`.
- Notebook activity `externalReferences.connection` uses
  `@pipeline().libraryVariables.notebook_execution_connection_id`.
- SQL activities continue to use the **same-workspace** workspace ID placeholder
  `00000000-0000-0000-0000-000000000000`; do **not** replace it with a
  DEV workspace GUID.
- The **source and target data connections** for Copy still come from
  `control.connection_settings`, passed by the Object Controller. Source
  `connectionId`, target Lakehouse `connectionId`, and source/target item
  metadata must be set correctly **per environment** in that SQL control table.
  They are not the same as the four framework-runtime variables.
- Same-workspace Invoke target `pipelineId` and Notebook `notebookId` remain
  Fabric item references, not connection IDs. Do not replace them with any of
  these four variable values. Validate item remapping when deploying to a new
  workspace; Library variables alone do not prove all cross-workspace item
  references are correct.

## DEV setup

1. Git sync `vl_ingestion_connections.VariableLibrary` into the Personal DEV
   Fabric workspace **before syncing/validating the updated pipelines**.
2. In the Variable Library UI, confirm all four types are `String`. Set their
   real environment-specific GUIDs in the active `Default` value set.
3. Open every relevant Pipeline > **Library variables** and verify that all
   declared references resolve. **Do not** replace the Library expressions
   with raw DEV GUIDs.
4. Verify one Control SQL Stored Procedure and one Control Lookup:
   - Connection: `@pipeline().libraryVariables.ingestion_control_connection_id`
   - Workspace ID: `00000000-0000-0000-0000-000000000000`
   - SQL Database ID: `@pipeline().libraryVariables.ingestion_control_item_id`
5. Verify an Invoke Pipeline activity uses
   `@pipeline().libraryVariables.pipeline_invoke_connection_id`.
   Its target pipeline still needs to point to the correct Fabric item.
6. Verify Notebook activities use
   `@pipeline().libraryVariables.notebook_execution_connection_id`.
   Their Notebook selection stays a same-workspace Fabric item reference;
   data Lakehouse IDs still come from target metadata. Confirm this dynamic
   Notebook Connection expression in the Fabric UI and on a real test run.
7. Run `pl_ingest_orchestrator` with the normal DEV request inputs, not runtime
   connection ID parameters. Avoid direct child runs.

## UAT / PROD deployment

Deploy/sync the same Pipeline and Variable Library definitions to each
environment, then set **that workspace's** four Library String values and
its `control.connection_settings` rows to that environment's connections.
A Fabric Variable Library may use separate value sets, but only one is active
per workspace; a deployment does not automatically select the correct set.
Re-check the active value set, permissions, SQL Database item ID, Invoke
targets, and Notebook item references **after** deployment.

Do not use the preview `Connection reference` variable type as a substitute
for the four String GUID variables without independently validating support
for all of these Data Pipeline consumers.

## Acceptance / release gate

- [ ] Master without one required Library value fails early with
      `MISSING_RUNTIME_BINDING`, before SQL/Copy/Notebook work.
- [ ] Control SQL Lookup and Stored Procedure validate and execute.
- [ ] Invoke Pipeline connects to the intended child.
- [ ] Notebook activity validates and executes with its dynamic Connection;
      verify Notebook permissions separately from target Lakehouse permission.
- [ ] DATABASE FULL + INCREMENTAL, FILE FULL + INCREMENTAL, and explicit +
      all-active requests exercise their existing SUCCESS/FAILED/SKIPPED paths.
- [ ] SQL Audit / Watermark semantics and Copy metadata connections remain unchanged.
- [ ] UAT/PROD deployment has correct active Library values and item rebinding.

**Git/static implementation is not Fabric runtime validation.** Stop release if
the Fabric designer rejects a dynamic Connection or a reference resolves to
the wrong item. Record the exact validation message; do not silently hardcode
a DEV GUID as a workaround.

Reference implementation: the TGH framework's Variable Library pattern.
Fabric references:
- https://learn.microsoft.com/en-us/fabric/data-factory/variable-library-integration-with-data-pipelines
- https://learn.microsoft.com/en-us/fabric/cicd/variable-library/value-sets
- https://learn.microsoft.com/en-us/fabric/cicd/variable-library/connection-reference-variable-type
