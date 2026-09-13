#!/usr/bin/env bash
# ==============================================================================
# Local Slim CI & State Deferral Demonstration Script
# ==============================================================================
# This script demonstrates dbt Slim CI completely LOCALLY without needing
# to push code to GitHub or S3.
#
# Concept:
# 1. Baseline State: Generates a baseline manifest.json (representing 'Prod')
# 2. Local Change: Modifies an upstream model (stg_orders.sql)
# 3. State Comparison: Runs 'dbt build --select state:modified+ --defer --state ...'
# 4. Result: Only modified models & downstream dependencies run; unmodified
#    upstream models are skipped & deferred to baseline tables!
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DBT_DIR="$ROOT_DIR/dbt_project"
STATE_DIR="$SCRIPT_DIR/state_artifacts"

# Set isolated home / profiles dir for portable execution
LOCAL_HOME="$ROOT_DIR/../../.tmp_home"
mkdir -p "$LOCAL_HOME/.dbt"
export HOME="$LOCAL_HOME"
export DBT_PROFILES_DIR="$DBT_DIR"

echo "========================================================================"
echo " STEP 1: Building Baseline Production State & Exporting Manifest"
echo "========================================================================"
cd "$DBT_DIR"

# 1. Build initial complete state
dbt seed --target dev_local
dbt build --target dev_local

# 2. Save baseline manifest
mkdir -p "$STATE_DIR"
cp target/manifest.json "$STATE_DIR/manifest.json"
echo "Baseline manifest saved to: $STATE_DIR/manifest.json"
echo ""

echo "========================================================================"
echo " STEP 2: Simulating a Developer Code Change in Staging Layer"
echo "========================================================================"
TARGET_FILE="$DBT_DIR/models/staging/stg_orders.sql"
BACKUP_FILE="$DBT_DIR/models/staging/stg_orders.sql.bak"

# Backup original file
cp "$TARGET_FILE" "$BACKUP_FILE"

# Make a modification: add an extra computed column 'is_credit_card'
cat << 'EOF' > "$TARGET_FILE"
with source as (
    select * from {{ source('raw_data', 'orders') }}
),

renamed as (
    select
        cast(id as {{ dbt.type_string() }}) as order_id,
        cast(customer_id as {{ dbt.type_string() }}) as customer_id,
        cast(order_date as date) as order_date,
        lower(trim(cast(status as {{ dbt.type_string() }}))) as order_status,
        cast(amount_cents as {{ dbt.type_numeric() }}) / 100.0 as order_amount_usd,
        lower(trim(cast(payment_method as {{ dbt.type_string() }}))) as payment_method,
        case when lower(trim(cast(payment_method as {{ dbt.type_string() }}))) = 'credit_card' then 1 else 0 end as is_credit_card
    from source
)

select * from renamed
EOF

echo "Modified $TARGET_FILE (added is_credit_card column)."
echo ""

echo "========================================================================"
echo " STEP 3: Executing Slim CI (state:modified+ with --defer)"
echo "========================================================================"
echo "Command:"
echo "dbt build --select state:modified+ --defer --state $STATE_DIR --target dev_local"
echo "------------------------------------------------------------------------"

dbt build \
  --select "state:modified+" \
  --defer \
  --state "$STATE_DIR" \
  --target dev_local

echo ""
echo "========================================================================"
echo " STEP 4: Restoring Staging Model & Cleanup"
echo "========================================================================"
mv "$BACKUP_FILE" "$TARGET_FILE"
echo "Restored $TARGET_FILE to clean state."
echo ""
echo "Slim CI Demonstration Complete! Notice that seeds and stg_customers were SKIPPED,"
echo "and only stg_orders and its downstream dependencies were selected & built."
