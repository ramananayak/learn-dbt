#!/usr/bin/env bash
# ==============================================================================
# Week 4 Verification Suite: dbt Mesh, Model Contracts & Legacy Migration
# ==============================================================================
# Runs both the finance_platform and marketing_analytics projects and
# demonstrates:
#   1. Contract enforcement (compile-time schema validation)
#   2. Legacy migration reconciliation (compare_legacy_vs_dbt analysis)
#   3. Model versioning (v1 and v2 deployed side-by-side)
#   4. Cross-project reference pattern (marketing consuming finance public model)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$SCRIPT_DIR/../../venv/bin/activate"

if [ -f "$VENV" ]; then
    source "$VENV"
fi

FINANCE_DIR="$SCRIPT_DIR/finance_platform"
MARKETING_DIR="$SCRIPT_DIR/marketing_analytics"

# ── Part 1: Finance Platform ──────────────────────────────────────────────────
echo "========================================================================"
echo " [1/4] Finance Platform — Install Packages"
echo "========================================================================"
cd "$FINANCE_DIR"
export DBT_PROFILES_DIR="$FINANCE_DIR"
dbt deps

echo ""
echo "========================================================================"
echo " [2/4] Finance Platform — Seed, Build & Test (with contract enforcement)"
echo "========================================================================"
dbt seed --target dev_local
dbt build --target dev_local

echo ""
echo "========================================================================"
echo " [3/4] Finance Platform — Compile Legacy Migration Analysis"
echo "========================================================================"
dbt compile --select compare_legacy_vs_dbt --target dev_local
echo ""
echo "  [INFO] Compiled SQL written to: target/compiled/finance_platform/analysis/compare_legacy_vs_dbt.sql"
echo "  [INFO] Run that SQL in your DuckDB client to see the reconciliation report."
echo ""
echo "  Expected output:"
echo "    match_status       | row_count"
echo "    -------------------+----------"
echo "    in_legacy_only     | 0         ← legacy rows missing from dbt"
echo "    in_dbt_only        | 0         ← dbt rows not in legacy"
echo "    in_both            | 12        ← all rows match"
echo "    value_discrepancies| 0         ← no revenue differences > \$0.01"

# ── Part 2: Marketing Analytics (Cross-Project Mesh Consumer) ─────────────────
echo ""
echo "========================================================================"
echo " [4/4] Marketing Analytics — Build (cross-project consumer)"
echo "========================================================================"
cd "$MARKETING_DIR"
export DBT_PROFILES_DIR="$MARKETING_DIR"
dbt deps
dbt seed --target dev_local
dbt build --target dev_local

echo ""
echo "========================================================================"
echo " ALL WEEK 4 CHECKS PASSED SUCCESSFULLY!"
echo ""
echo " What was demonstrated:"
echo "   ✓ finance_platform: contract-enforced fct_revenue (public model)"
echo "   ✓ finance_platform: fct_revenue_v1 and fct_revenue_v2 side-by-side"
echo "   ✓ finance_platform: legacy migration analysis compiled"
echo "   ✓ marketing_analytics: cross-project revenue + segment join"
echo "========================================================================"
