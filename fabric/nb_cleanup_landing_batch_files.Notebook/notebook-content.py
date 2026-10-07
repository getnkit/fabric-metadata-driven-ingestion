# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   }
# META }

# PARAMETERS CELL ********************

p_workspace_id = ""
p_lakehouse_id = ""
p_landing_relative_path = ""
p_batch_id = ""

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

def _require_nonempty(name, value):
    if value is None or str(value).strip() == "":
        raise ValueError(f"{name} is required.")
    return str(value).strip()


def _require_safe_path_segment(name, value):
    value = _require_nonempty(name, value)
    if value in {".", ".."} or "/" in value or "\\" in value:
        raise ValueError(f"{name} contains an invalid path segment: {value!r}")
    return value


workspace_id = _require_safe_path_segment("p_workspace_id", p_workspace_id)
lakehouse_id = _require_safe_path_segment("p_lakehouse_id", p_lakehouse_id)
batch_id = _require_nonempty("p_batch_id", p_batch_id)
landing_relative_path = _require_nonempty(
    "p_landing_relative_path",
    p_landing_relative_path,
).strip("/")

path_segments = [segment for segment in landing_relative_path.split("/") if segment]
if not path_segments or any(segment in {".", ".."} for segment in path_segments):
    raise ValueError("p_landing_relative_path is not a safe Landing batch path.")

expected_batch_segment = f"batch_id={batch_id}"
if path_segments[-1] != expected_batch_segment:
    raise ValueError(
        "p_landing_relative_path must end with the current batch_id segment: "
        f"{expected_batch_segment}"
    )

landing_path = (
    f"abfss://{workspace_id}@onelake.dfs.fabric.microsoft.com/"
    f"{lakehouse_id}/Files/{landing_relative_path}"
)

# Compensating cleanup is intentionally scoped to the failed batch folder only.
if notebookutils.fs.exists(landing_path):
    notebookutils.fs.rm(landing_path, True)

if notebookutils.fs.exists(landing_path):
    raise RuntimeError(
        f"LANDING_CLEANUP_INCOMPLETE: batch_id={batch_id} path={landing_relative_path}"
    )

print(
    f"LANDING_CLEANUP_SUCCESS batch_id={batch_id} "
    f"path={landing_relative_path}"
)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
