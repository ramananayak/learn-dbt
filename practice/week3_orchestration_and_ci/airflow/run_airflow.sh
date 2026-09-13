#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COMMAND="${1:-start}"

case "$COMMAND" in
  start)
    echo "=========================================================="
    echo " Starting Lightweight Airflow + Cosmos (Standalone Mode) "
    echo "=========================================================="
    docker compose up -d --build
    echo ""
    echo "Waiting for Airflow database initialization..."
    for i in {1..30}; do
      if docker compose exec -T airflow test -f /opt/airflow/standalone_admin_password.txt 2>/dev/null; then
        break
      fi
      sleep 2
    done
    docker compose exec -T airflow airflow users create --username admin --password admin --firstname Admin --lastname User --role Admin --email admin@example.com 2>/dev/null || \
    docker compose exec -T airflow airflow users reset-password --username admin --password admin 2>/dev/null || true
    echo ""
    echo "Airflow is ready in the background!"
    echo "Web UI URL : http://localhost:8080"
    echo "Username   : admin"
    echo "Password   : admin"
    echo ""
    echo "To inspect live logs, run: ./run_airflow.sh logs"
    echo "To stop Airflow, run:       ./run_airflow.sh stop"
    ;;

  stop)
    echo "Stopping Airflow containers..."
    docker compose down
    echo "Airflow stopped."
    ;;

  logs)
    docker compose logs -f
    ;;

  status)
    docker compose ps
    ;;

  test)
    echo "Running Cosmos DAG test inside Airflow container..."
    docker compose exec airflow airflow dags test dbt_cosmos_duckdb_pipeline 2026-01-01
    ;;

  *)
    echo "Usage: $0 {start|stop|logs|status|test}"
    exit 1
    ;;
esac
