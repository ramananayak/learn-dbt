"""
Airflow Cosmos Dynamic DAG: Local Development & DuckDB Pipeline
---------------------------------------------------------------
This DAG leverages Astronomer Cosmos to parse the dbt project and
automatically generate individual Airflow tasks for every seed,
model, and test in the dbt graph.
"""

import shutil
from datetime import datetime
from pathlib import Path
from airflow.decorators import dag
from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, ExecutionConfig, RenderConfig
from cosmos.constants import TestBehavior

# Path inside container (or local path fallback)
DEFAULT_DBT_ROOT = Path("/opt/airflow/dbt_project")
if not DEFAULT_DBT_ROOT.exists():
    # Local fallback for dry-running outside container
    DEFAULT_DBT_ROOT = Path(__file__).resolve().parent.parent.parent / "dbt_project"

DBT_BIN = Path("/opt/airflow/dbt_venv/bin/dbt")
if not DBT_BIN.exists():
    DBT_BIN = Path(shutil.which("dbt") or "dbt")

profile_config = ProfileConfig(
    profile_name="platform_dbt_project",
    target_name="dev_local",
    profiles_yml_filepath=DEFAULT_DBT_ROOT / "profiles.yml",
)

@dag(
    dag_id="dbt_cosmos_duckdb_pipeline",
    schedule_interval="@daily",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["dbt", "cosmos", "duckdb", "local_development"],
    doc_md=__doc__,
)
def dbt_analytics_dag():
    dbt_models = DbtTaskGroup(
        group_id="dbt_transforms",
        project_config=ProjectConfig(dbt_project_path=DEFAULT_DBT_ROOT),
        profile_config=profile_config,
        execution_config=ExecutionConfig(
            dbt_executable_path=DBT_BIN,
        ),
        render_config=RenderConfig(
            test_behavior=TestBehavior.AFTER_EACH,
        ),
    )

dbt_analytics_dag()
