"""
Airflow Cosmos Dynamic DAG: Cloud Data Warehouse (AWS Redshift)
---------------------------------------------------------------
This DAG illustrates production orchestration targeting AWS Redshift
using Astronomer Cosmos's native RedshiftUserPasswordProfileMapping.
Connection parameters are managed securely via Airflow Connection 'redshift_default'.
"""

import shutil
from datetime import datetime
from pathlib import Path
from airflow.decorators import dag
from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, ExecutionConfig, RenderConfig
from cosmos.profiles import RedshiftUserPasswordProfileMapping

# Path inside container (or local path fallback)
DEFAULT_DBT_ROOT = Path("/opt/airflow/dbt_project")
if not DEFAULT_DBT_ROOT.exists():
    DEFAULT_DBT_ROOT = Path(__file__).resolve().parent.parent.parent / "dbt_project"

DBT_BIN = Path("/opt/airflow/dbt_venv/bin/dbt")
if not DBT_BIN.exists():
    DBT_BIN = Path(shutil.which("dbt") or "dbt")

profile_config = ProfileConfig(
    profile_name="platform_dbt_project",
    target_name="dev_redshift",
    profiles_yml_filepath=DEFAULT_DBT_ROOT / "profiles.yml",
)

@dag(
    dag_id="dbt_cosmos_redshift_pipeline",
    schedule_interval="@daily",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["dbt", "cosmos", "redshift", "production"],
    doc_md=__doc__,
)
def dbt_redshift_analytics_dag():
    dbt_models = DbtTaskGroup(
        group_id="transform_core_redshift",
        project_config=ProjectConfig(dbt_project_path=DEFAULT_DBT_ROOT),
        profile_config=profile_config,
        execution_config=ExecutionConfig(
            dbt_executable_path=DBT_BIN,
        ),
    )

dbt_redshift_analytics_dag()
