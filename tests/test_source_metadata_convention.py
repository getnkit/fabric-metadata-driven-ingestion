"""Static regression checks for metadata-driven source selection and routing.

Run from repository root:
    python -m unittest discover -s tests -v

These checks do not substitute for live Fabric SQL / SFTP integration tests.
"""

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_pipeline(name):
    file = ROOT / "fabric" / (name + ".DataPipeline") / "pipeline-content.json"
    return json.loads(file.read_text(encoding="utf-8"))["properties"]


def activities(items):
    for activity in items:
        yield activity
        properties = activity.get("typeProperties", {})
        for key in ("ifTrueActivities", "ifFalseActivities", "activities", "defaultActivities"):
            yield from activities(properties.get(key, []))
        for case in properties.get("cases", []):
            yield from activities(case.get("activities", []))


class SourceMetadataConventionTests(unittest.TestCase):
    SFTP_PIPELINES = (
        "pl_ingest_sftp_full_adapter",
        "pl_ingest_sftp_incremental_adapter",
    )

    def test_sftp_adapters_fail_fast_before_copy(self):
        for pipeline_name in self.SFTP_PIPELINES:
            with self.subTest(pipeline=pipeline_name):
                pipeline = load_pipeline(pipeline_name)
                top_level = {a["name"]: a for a in pipeline["activities"]}
                self.assertIn("if_valid_file_name_pattern", top_level)
                gate = top_level["if_valid_file_name_pattern"]
                self.assertEqual(gate["type"], "IfCondition")
                self.assertEqual(
                    gate["dependsOn"][0]["activity"],
                    "if_supported_file_format",
                )
                expression = gate["typeProperties"]["expression"]["value"]
                self.assertIn("p_file_name_pattern", expression)
                self.assertIn("trim(", expression)
                self.assertIn("empty(", expression)
                self.assertNotIn("p_source_object", expression)
                branches = {
                    a["name"]: a for a in gate["typeProperties"]["ifFalseActivities"]
                }
                procedure = branches["sp_finalize_invalid_file_name_pattern"]
                parameters = procedure["typeProperties"]["storedProcedureParameters"]
                self.assertEqual(
                    parameters["error_code"]["value"], "INVALID_FILE_NAME_PATTERN"
                )
                self.assertEqual(parameters["status"]["value"], "FAILED")
                self.assertEqual(parameters["advance_watermark"]["value"], "false")
                fail = branches["fail_invalid_file_name_pattern"]
                self.assertEqual(fail["type"], "Fail")
                self.assertEqual(
                    fail["dependsOn"][0]["activity"], procedure["name"]
                )
                self.assertEqual(
                    top_level["set_ingestion_timestamp"]["dependsOn"][0]["activity"],
                    gate["name"],
                )
                copy = top_level["copy_sftp_to_landing"]
                self.assertEqual(
                    copy["typeProperties"]["source"]["storeSettings"]
                    ["wildcardFileName"]["value"],
                    "@pipeline().parameters.p_file_name_pattern",
                )

    def test_metadata_sql_enforces_file_only_without_changing_watermarks(self):
        sql_files = (
            "scripts/control/01_create_control_schema.sql",
            "fabric/sqldb_ingestion_control.SQLDatabase/control/Tables/ingestion_config.sql",
            "scripts/control/migrations/008_require_file_name_pattern.sql",
        )
        for file in sql_files:
            with self.subTest(file=file):
                sql = (ROOT / file).read_text(encoding="utf-8")
                self.assertIn("CK_ingestion_config_file_name_pattern", sql)
                self.assertRegex(sql, r"(?i)TRIM\(JSON_VALUE\(")
                self.assertIn("'$.file_name_pattern'", sql)
                self.assertIn("ingestion_pattern", sql)
                self.assertIn("source_options", sql)
        migration = (ROOT / sql_files[-1]).read_text(encoding="utf-8").upper()
        self.assertNotIn("UPDATE CONTROL.PIPELINE_WATERMARKS", migration)
        self.assertNotIn("DELETE FROM CONTROL.PIPELINE_WATERMARKS", migration)
        self.assertNotIn("DROP TABLE CONTROL.INGESTION_CONFIG", migration)

    def test_database_selection_is_unchanged(self):
        database = load_pipeline("pl_ingest_azure_sql_full_adapter")
        self.assertIn("p_source_schema", database["parameters"])
        self.assertIn("p_source_object", database["parameters"])
        self.assertNotIn("p_file_name_pattern", database["parameters"])
        file_router = load_pipeline("pl_ingest_file_router")
        self.assertIn("p_source_object", file_router["parameters"])
        self.assertIn("p_source_path", file_router["parameters"])
        self.assertIn("p_source_options", file_router["parameters"])

        controller = load_pipeline("pl_ingest_object_controller")
        lookup = next(
            a for a in controller["activities"]
            if a["name"] == "lkp_ingestion_config"
        )
        lookup_sql = lookup["typeProperties"]["source"]["sqlReaderQuery"]["value"]
        self.assertIn("$.file_name_pattern", lookup_sql)
        self.assertIn("AS file_name_pattern", lookup_sql)
        for obj in activities(controller["activities"]):
            if obj["name"] == "inv_ingest_file_router":
                self.assertIn("p_file_name_pattern", obj["typeProperties"]["parameters"])
        self.assertIn("p_file_name_pattern", file_router["parameters"])
        for name in self.SFTP_PIPELINES:
            self.assertIn("p_file_name_pattern", load_pipeline(name)["parameters"])

    def test_seed_keeps_stable_file_feed_and_explicit_patterns(self):
        sql = (ROOT / "scripts/control/04_seed_ingestion_metadata.sql").read_text(
            encoding="utf-8"
        )
        self.assertIn("'inventory_snapshot'", sql)
        self.assertIn("'inventory_movement'", sql)
        self.assertIn("inventory_snapshot.csv", sql)
        self.assertIn("inventory_movement_*.csv", sql)
        self.assertIn("w.last_watermark_value = @InitialFileWatermark", sql)
        # Baseline seed behavior is intentionally untouched; never rerun it
        # solely for the new FILE filename-pattern constraint.

    def test_no_runtime_fallback_to_source_object(self):
        for name in self.SFTP_PIPELINES:
            with self.subTest(pipeline=name):
                pipeline = load_pipeline(name)
                copy = next(
                    a for a in activities(pipeline["activities"])
                    if a["name"] == "copy_sftp_to_landing"
                )
                selector = copy["typeProperties"]["source"]["storeSettings"]["wildcardFileName"]["value"]
                self.assertNotIn("p_source_object", selector)
                self.assertNotIn("coalesce(", selector)
                self.assertNotIn("if(", selector)


if __name__ == "__main__":
    unittest.main()
