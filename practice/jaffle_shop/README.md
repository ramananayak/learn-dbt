# 🥪 The Jaffle Shop 🦘

_powered by the dbt Fusion engine_

Welcome! This is a sandbox project for exploring the basic functionality of Fusion. It's based on a fictional restaurant called the Jaffle Shop that serves [jaffles](https://en.wikipedia.org/wiki/Pie_iron).

To get started:
1. Set up your database connection in `~/.dbt/profiles.yml`.
2. Initialze jaffle project by running `dbt init --skip-profile-setup`, then
   edit the generated `dbt_project.yml` to replace profile: jaffle_shop with profile: <YOUR-PROFILE-NAME>.
3. Run below commands in order

```bash
Navigate into your project folder:

  cd practice/jaffle_shop

Execute the following commands in order:

  # 1. Install required packages (dbt-utils)
  dbt deps

  # 2. Test database connection
  dbt debug

  # 3. Load the sample CSVs from seeds/ into DuckDB
  dbt seed

  # 4. Build all staging and marts models
  dbt run

  # 5. Run all schema and data tests
  dbt test

  # Or run seed, run, and test in a single execution:
  dbt build
```

> [!NOTE]
> If you're brand-new to dbt, we recommend starting with the [dbt Learn](https://learn.getdbt.com/) platform. It's a free, interactive way to learn dbt, and it's a great way to get started if you're new to the tool.

## Dataset

Six CSV seeds describe a fictional food shop with locations across the US:

| Seed | Rows | Contents |
|------|------|----------|
| `raw_customers` | 100 | UUID IDs and customer names |
| `raw_orders` | 688 | Orders with store, customer, subtotal/tax/total stored in cents |
| `raw_products` | 10 | 5 jaffles (`JAF-001`–`JAF-005`, $11–$14) and 5 beverages (`BEV-001`–`BEV-005`, $4–$7) |
| `raw_stores` | 6 | Philadelphia, Brooklyn, Chicago, San Francisco, New Orleans, Los Angeles |
| `raw_items` | ~1,800 | Line items linking orders to product SKUs |
| `raw_supplies` | ~30 | Per-SKU ingredient costs |

Seeds land in `<schema>_raw` (configured via `+schema: raw` in `dbt_project.yml`), keeping raw tables cleanly namespaced away from transformed models.

## Project structure

```
seeds/             ← raw CSVs → loaded into <schema>_raw
models/
├── staging/       ← clean and rename raw columns (materialized as views)
│   ├── __sources.yml       ← source declarations with freshness SLAs
│   ├── stg_customers.sql
│   ├── stg_orders.sql      ← cents_to_dollars macro applied here
│   ├── stg_order_items.sql
│   ├── stg_locations.sql
│   ├── stg_products.sql
│   └── stg_supplies.sql
└── marts/         ← business logic and aggregations (materialized as tables)
    ├── customers.sql        ← lifetime spend, order count, customer_type flag
    ├── orders.sql           ← food/drink flags, per-customer order sequence
    ├── order_items.sql
    ├── locations.sql
    ├── products.sql
    └── supplies.sql
macros/
└── cents_to_dollars.sql    ← adapter-dispatched macro (DuckDB, Postgres, Redshift, BigQuery, Spark)
```

## Key concepts demonstrated

- **Cross-adapter macros** — `cents_to_dollars` dispatches to the right SQL dialect at compile time (`::numeric` on DuckDB/Postgres, `round(/ 100, 2)` on Spark/BigQuery). Model code stays identical across adapters.
- **`dbt.type_string()` / `dbt.type_numeric()`** — built-in cross-database type helpers used in staging casts instead of dialect-specific `varchar`/`decimal`.
- **Source freshness** — `raw_orders` warns after 12 h and errors after 24 h via `loaded_at_field: ordered_at`. Run `dbt source freshness` to check.
- **Expression tests** — `order_total - tax_paid = subtotal` enforced as a first-class schema test on `stg_orders`; no external test runner needed.
- **Computed columns belong in marts** — `customer_type` (`new` vs `returning`), `is_food_order`, and `is_drink_order` flags live in the mart layer; staging models stay free of business logic.

## Sample output

After `dbt build`, the `customers` mart has one row per customer with lifetime metrics:

```
 customer_name    | count_lifetime_orders | lifetime_spend | customer_type
------------------+-----------------------+----------------+---------------
 Aaron Gardner    |                     1 |          95.40 | new
 Stephanie Love   |                     2 |          19.07 | returning
 Douglas Hill     |                     5 |          60.23 | returning
 ...
(100 rows)
```

The `orders` mart adds food/drink classification and per-customer order sequence:

```
 order_id (short) | order_date | order_total | is_food_order | is_drink_order | customer_order_number
------------------+------------+-------------+---------------+----------------+----------------------
 9bed808a         | 2016-09-01 |        7.42 | true          | false          |                     1
 b83630c1         | 2016-09-01 |        7.42 | true          | true           |                     1
 ...
(688 rows)
```
