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
target_table = _require_safe_path_segment("p_target_table", p_target_table)
batch_id = _require_nonempty("p_batch_id", p_batch_id)

schema = "" if p_target_schema is None else str(p_target_schema).strip()
if schema:
    schema = _require_safe_path_segment("p_target_schema", schema)
    table_relative_path = f"{schema}/{target_table}"
else:
    table_relative_path = target_table

table_path = (
    f"abfss://{workspace_id}@onelake.dfs.fabric.microsoft.com/"
    f"{lakehouse_id}/Tables/{table_relative_path}"
)

batch_predicate = F.col("_batch_id") == F.lit(batch_id)

rows_before = (
    spark.read.format("delta")
    .load(table_path)
    .where(batch_predicate)
    .count()
)

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

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
