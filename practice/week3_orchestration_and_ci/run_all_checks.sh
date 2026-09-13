#!/usr/bin/env bash
# ==============================================================================
# Week 3 Verification Suite: Airflow Cosmos & Slim CI/CD
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Set isolated home / profile paths
LOCAL_HOME="$ROOT_DIR/.tmp_home"
mkdir -p "$LOCAL_HOME/.dbt"
export HOME="$LOCAL_HOME"
export DBT_PROFILES_DIR="$SCRIPT_DIR/dbt_project"

echo "========================================================================"
echo " [1/3] Verifying dbt Project Compilation & Full Build"
echo "========================================================================"
cd "$SCRIPT_DIR/dbt_project"
dbt seed --target dev_local
dbt build --target dev_local

echo ""
echo "========================================================================"
echo " [2/3] Verifying Airflow Cosmos DAG Syntax & Definitions"
echo "========================================================================"
cd "$SCRIPT_DIR"
python3 -c "
import ast
for dag_file in ['airflow/dags/dbt_cosmos_dag.py', 'airflow/dags/dbt_cosmos_redshift_dag.py']:
    with open(dag_file, 'r') as f:
        ast.parse(f.read())
    print(f'  [OK] Valid Python syntax: {dag_file}')
"

echo ""
echo "========================================================================"
echo " [3/3] Executing Local Slim CI & State Deferral Simulation"
echo "========================================================================"
cd "$SCRIPT_DIR/ci_cd"
./run_slim_ci_local.sh

echo ""
echo "========================================================================"
echo " ALL WEEK 3 CHECKS PASSED SUCCESSFULLY! "
echo "========================================================================"
