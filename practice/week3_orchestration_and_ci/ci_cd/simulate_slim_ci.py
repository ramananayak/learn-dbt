#!/usr/bin/env python3
"""
Slim CI State Inspector & Concept Explainer
-------------------------------------------
This utility inspects the dbt compilation artifacts (manifest.json)
to explain how dbt detects modified nodes and resolves dependencies.
"""

import json
import sys
from pathlib import Path

def main():
    script_dir = Path(__file__).resolve().parent
    root_dir = script_dir.parent
    dbt_target_manifest = root_dir / "dbt_project" / "target" / "manifest.json"
    state_manifest = script_dir / "state_artifacts" / "manifest.json"

    print("=" * 70)
    print(" dbt Slim CI State Inspector ")
    print("=" * 70)

    if not state_manifest.exists():
        print(f"[!] Baseline manifest not found at: {state_manifest}")
        print("    Please run ./run_slim_ci_local.sh first to generate the baseline state.")
        return 0

    with open(state_manifest, "r") as f:
        baseline_data = json.load(f)

    baseline_nodes = baseline_data.get("nodes", {})
    models = {k: v for k, v in baseline_nodes.items() if k.startswith("model.")}
    seeds = {k: v for k, v in baseline_nodes.items() if k.startswith("seed.")}
    tests = {k: v for k, v in baseline_nodes.items() if k.startswith("test.")}

    print(f"\n[+] Baseline 'Production' Manifest Stats:")
    print(f"    - Models : {len(models)}")
    print(f"    - Seeds  : {len(seeds)}")
    print(f"    - Tests  : {len(tests)}")
    print(f"    - Total Nodes: {len(baseline_nodes)}")

    print("\n[+] Node Dependency Graph (Lineage):")
    for node_id, node_info in models.items():
        depends_on = node_info.get("depends_on", {}).get("nodes", [])
        clean_deps = [d.split(".")[-1] for d in depends_on]
        model_name = node_id.split(".")[-1]
        print(f"    - {model_name:25} <-- depends on: {clean_deps if clean_deps else 'None'}")

    print("\n[+] How dbt Resolves 'state:modified+':")
    print("    1. State Comparison: dbt computes a checksum of SQL/YAML for each node.")
    print("    2. Change Detection: If stg_orders.sql is modified, its checksum changes.")
    print("    3. Graph Traversal (+): dbt traces all downstream children:")
    print("       stg_orders -> int_customer_order_summary -> dim_customers")
    print("       stg_orders -> fct_daily_sales")
    print("    4. State Deferral (--defer): Unmodified parents (like stg_customers & raw seeds)")
    print("       are resolved from the baseline production database/schema without rebuilding.")

    print("=" * 70)
    return 0

if __name__ == "__main__":
    sys.exit(main())
