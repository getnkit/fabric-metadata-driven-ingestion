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
p_target_schema = ""
p_target_table = ""
p_batch_id = ""

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

from delta.tables import DeltaTable
from pyspark.sql import functions as F


# Validate identifiers before constructing the OneLake Delta path.
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
target_schema = _require_safe_path_segment("p_target_schema", p_target_schema)
target_table = _require_safe_path_segment("p_target_table", p_target_table)
batch_id = _require_nonempty("p_batch_id", p_batch_id)

table_relative_path = f"{target_schema}/{target_table}"

table_path = (
    f"abfss://{workspace_id}@onelake.dfs.fabric.microsoft.com/"
    f"{lakehouse_id}/Tables/{table_relative_path}"
)

# Compensating cleanup is intentionally scoped to one failed ingestion batch.
batch_predicate = F.col("_batch_id") == F.lit(batch_id)


def _cleanup_batch_rows():
    try:
        target_df = spark.read.format("delta").load(table_path)
    except Exception as exc:
        error_message = str(exc)
        # A missing target means the failed write produced nothing to compensate.
        if "[PATH_NOT_FOUND]" in error_message or "Path does not exist:" in error_message:
            print(
                f"BRONZE_CLEANUP_NOOP batch_id={batch_id} "
                f"target={table_relative_path} reason=TARGET_NOT_FOUND"
            )
            return
        raise

    rows_before = target_df.where(batch_predicate).count()

    # Delete only this batch, then verify that no partial Bronze rows remain.
    if rows_before > 0:
        DeltaTable.forPath(spark, table_path).delete(batch_predicate)

    rows_after = (
        spark.read.format("delta")
        .load(table_path)
        .where(batch_predicate)
        .count()
    )

    if rows_after != 0:
        raise RuntimeError(
            f"BRONZE_CLEANUP_INCOMPLETE: batch_id={batch_id} still has {rows_after} row(s) "
            f"in {table_relative_path}."
        )

    print(
        f"BRONZE_CLEANUP_SUCCESS batch_id={batch_id} "
        f"target={table_relative_path} rows_removed={rows_before}"
    )

_cleanup_batch_rows()

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
