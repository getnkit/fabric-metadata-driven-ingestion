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


# Validate pipeline-supplied values before using them in paths or reader options.
def _require_nonempty(name, value):
    if value is None or str(value).strip() == "":
        raise ValueError(f"{name} is required.")
    return str(value).strip()


def _require_safe_path_segment(name, value):
    value = _require_nonempty(name, value)
    if value in {".", ".."} or "/" in value or "\\" in value:
        raise ValueError(f"{name} contains an invalid path segment: {value!r}")
    return value


def _require_single_char(name, value):
    if not isinstance(value, str) or len(value) != 1:
        raise ValueError(f"{name} must be a single character.")
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

# Keep format-specific parsing behind a small reader interface so routing stays metadata-driven.
def _read_delimited_text(path, options):
    delimiter = options.get("delimiter")
    has_header = options.get("has_header")
    encoding = options.get("encoding")
    quote = _require_single_char("source_options.quote", options.get("quote"))
    escape = _require_single_char("source_options.escape", options.get("escape"))

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
        .option("quote", quote)
        .option("escape", escape)
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

landing_root_path = (
    f"abfss://{workspace_id}@onelake.dfs.fabric.microsoft.com/"
    f"{lakehouse_id}/Files/{landing_relative_path}"
)
target_table_path = (
    f"abfss://{workspace_id}@onelake.dfs.fabric.microsoft.com/"
    f"{lakehouse_id}/Tables/{target_schema}/{target_table}"
)

# The adapter passes the batch-scoped Landing path; the notebook only parses and appends it to Bronze.
reader = READERS[file_format]
df = reader(landing_root_path, source_options)

landing_prefix = landing_root_path.rstrip("/") + "/"
relative_start = len(landing_prefix) + 1
# Fabric can expose OneLake file URIs with query metadata; strip it from lineage columns.
relative_file_path = F.regexp_replace(
    F.substring(F.input_file_name(), relative_start, 1000000),
    r"\?.*$",
    "",
)

df = (
    df
    .withColumn("_batch_id", F.lit(batch_id))
    .withColumn("_pipeline_run_id", F.lit(pipeline_run_id))
    .withColumn("_ingestion_timestamp", F.lit(ingestion_timestamp).cast("timestamp"))
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

# Count and write reuse the same DataFrame; always release the cache even when the append fails.
try:
    row_count = df.count()

    # Bronze ingestion is append-oriented; failed batches are compensated by the cleanup notebook.
    (
        df.write
        .format("delta")
        .mode("append")
        .save(target_table_path)
    )
finally:
    df.unpersist()

# source_row_count is the parsed Landing row count. After a successful atomic Delta append,
# target_row_count reuses that count; it is an audit metric, not an independent Bronze recount.
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
