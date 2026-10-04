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
p_source_root_path = ""
p_file_format = ""
p_source_options = ""
p_target_schema = ""
p_target_table = ""
p_batch_id = ""
p_pipeline_run_id = ""
p_ingestion_timestamp = ""

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

import json
from pyspark import StorageLevel
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


def _parse_source_options(raw_value):
    try:
        parsed = json.loads(_require_nonempty("p_source_options", raw_value))
    except json.JSONDecodeError as exc:
        raise ValueError("p_source_options must be valid JSON.") from exc

    if not isinstance(parsed, dict):
        raise ValueError("p_source_options must be a JSON object.")

    return parsed


# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

def _read_delimited_text(path, options):
    delimiter = options.get("delimiter")
    has_header = options.get("has_header")
    encoding = options.get("encoding")

    if not isinstance(delimiter, str) or delimiter == "":
        raise ValueError("source_options.delimiter is required for DELIMITED_TEXT.")
    if not isinstance(has_header, bool):
        raise ValueError("source_options.has_header must be boolean for DELIMITED_TEXT.")
    if not isinstance(encoding, str) or encoding.strip() == "":
        raise ValueError("source_options.encoding is required for DELIMITED_TEXT.")

    return (
        spark.read
        .option("recursiveFileLookup", "true")
        .option("header", str(has_header).lower())
        .option("sep", delimiter)
        .option("encoding", encoding)
        .option("quote", '"')
        .option("escape", "\\")
        .csv(path)
    )


READERS = {
    "DELIMITED_TEXT": _read_delimited_text,
}


# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

workspace_id = _require_safe_path_segment("p_workspace_id", p_workspace_id)
lakehouse_id = _require_safe_path_segment("p_lakehouse_id", p_lakehouse_id)
landing_relative_path = _require_nonempty(
    "p_landing_relative_path",
    p_landing_relative_path,
).strip("/")
source_root_path = _require_nonempty("p_source_root_path", p_source_root_path)
file_format = _require_nonempty("p_file_format", p_file_format).upper()
target_schema = _require_safe_path_segment("p_target_schema", p_target_schema)
target_table = _require_safe_path_segment("p_target_table", p_target_table)
batch_id = _require_nonempty("p_batch_id", p_batch_id)
pipeline_run_id = _require_nonempty("p_pipeline_run_id", p_pipeline_run_id)
ingestion_timestamp = _require_nonempty(
    "p_ingestion_timestamp",
    p_ingestion_timestamp,
)
source_options = _parse_source_options(p_source_options)

if file_format not in READERS:
    raise ValueError(
        f"Unsupported file format: {file_format}. "
        f"Supported formats: {', '.join(sorted(READERS))}."
    )

source_root_path = (
    source_root_path
    if source_root_path.endswith("/")
    else source_root_path + "/"
)

landing_root = (
    f"abfss://{workspace_id}@onelake.dfs.fabric.microsoft.com/"
    f"{lakehouse_id}/Files/{landing_relative_path}"
)
target_path = (
    f"abfss://{workspace_id}@onelake.dfs.fabric.microsoft.com/"
    f"{lakehouse_id}/Tables/{target_schema}/{target_table}"
)

reader = READERS[file_format]
df = reader(landing_root, source_options)

landing_prefix = landing_root.rstrip("/") + "/"
relative_start = len(landing_prefix) + 1
relative_file_path = F.substring(F.input_file_name(), relative_start, 1000000)

df = (
    df
    .withColumn("_batch_id", F.lit(batch_id))
    .withColumn("_pipeline_run_id", F.lit(pipeline_run_id))
    .withColumn("_ingestion_timestamp", F.lit(ingestion_timestamp))
    .withColumn(
        "_source_file_name",
        F.element_at(F.split(relative_file_path, "/"), -1),
    )
    .withColumn(
        "_source_file_path",
        F.concat(F.lit(source_root_path), relative_file_path),
    )
    .persist(StorageLevel.MEMORY_AND_DISK)
)

try:
    row_count = df.count()

    (
        df.write
        .format("delta")
        .mode("append")
        .save(target_path)
    )
finally:
    df.unpersist()

result = json.dumps(
    {
        "source_row_count": int(row_count),
        "target_row_count": int(row_count),
        "file_format": file_format,
    }
)

print(
    f"LANDING_TO_BRONZE_SUCCESS batch_id={batch_id} "
    f"format={file_format} target={target_schema}.{target_table} "
    f"rows_written={row_count}"
)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

notebookutils.notebook.exit(result)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
