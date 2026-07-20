
# Build log — Dealership data platform

A Bronze/Silver/Gold lakehouse for a fictional Nigerian used-car import dealership, built as an end-to-end portfolio project. This log documents the chronology, the bugs hit along the way, and the architectural decisions made in response to them.

## Stack

- Docker + Docker Compose, base image `quay.io/jupyter/pyspark-notebook` (Spark 4.1.0, Java 17)
- Delta Lake 4.1.0 (`delta-spark`) for table storage and ACID operations
- PySpark, run locally now, designed to migrate to Databricks later
- Faker for synthetic data generation
- Git/GitHub for version control

Repo: `github.com/Temitope96/car-dealership-product`

## Architecture at a glance

Bronze → Silver → Gold, path-based Delta tables under `spark-warehouse/{layer}.db/{table}`, read and written through a shared helper (`src/utils/lakehouse.py`) rather than Spark's SQL catalog. Two LLM-style agents were simulated on top of Bronze/Silver: a WhatsApp group ingestion agent (rule-based text classification standing in for an LLM) and a receipt/OCR intake agent (simulated OCR with an injected error rate), both feeding a shared `review_task` queue and a Gold `fact_review_queue`.

## Build phases

1. **Environment scaffold** — Docker image, `docker-compose.yml`, `requirements.txt`, repo init, `.devcontainer` for VS Code.
2. **Silver layer generation** (`notebooks/01_generate_sample_data.ipynb`) — 26 tables covering the full vehicle lifecycle: branch, staff, staff_role, auction_house, vendor, part, data_source, inspection_checklist_item, vehicle, purchase, shipment, port_arrival, pickup, office_intake, inspection, inspection_result, damage_item, repair_job, repair_job_damage, repair_job_part, cleaning_task, listing, customer, sale, payment, vehicle_stage_history.
3. **Gold layer star schema** (`notebooks/02_build_gold_layer.ipynb`) — `dim_date`, `dim_vehicle` (SCD2-structured), `dim_branch`, `dim_staff`, `dim_auction_house`, `dim_vendor`, `dim_part`, `dim_customer`, `dim_data_source`, `dim_expense_category`, `dim_payment_method`, `fact_purchase`, `fact_repair`, `fact_sale`, `fact_vehicle_lifecycle` (accumulating snapshot), `fact_profit`, `fact_profit_history` (append-only audit).
4. **Agent simulation** (`notebooks/03_whatsapp_receipt_agents.ipynb`) — `bronze.raw_message`, `silver.extracted_event`, `bronze.receipt_document`, `silver.extracted_receipt_line`, `silver.review_task`, `gold.fact_review_queue`.
5. **Executive dashboard mockup** — visual reference for the Power BI build, since Power BI Desktop wasn't yet installed.

## Final metrics (synthetic dataset, n=40 vehicles)

| Metric | Value |
|---|---|
| Vehicles sold | 15 |
| Total revenue | ₦145,513,395 |
| Total cost | ₦110,913,153 |
| Total profit | ₦34,600,242 |
| Avg margin | 22.91% |
| Avg days purchase → sale | 81.07 |
| Open review queue items | 4 |
| Stage funnel | Sold 15, Listed 9, In repair 6, At port 4, Shipped 4, Inspecting 2 |

## Bugs and fixes

### 1. Redundant/mismatched PySpark download in Docker build

**Symptom:** Build got stuck downloading a ~450MB `pyspark-4.2.0.tar.gz`, despite the base image already shipping Spark 4.1.0.

**Cause:** `pip install delta-spark` resolves its `pyspark>=4.0.1` dependency from PyPI. The base image installs Spark as a raw binary (`SPARK_HOME` + `PYTHONPATH`), not as a pip package, so pip has no record it's already there — it fetches its own copy, and picks the newest release rather than the version actually running.

**Fix:** Install `delta-spark` with `--no-deps`, then install the remaining packages (`faker`, `pandas`, `python-dotenv`) separately in the same `RUN` step.

### 2. `CANNOT_DETERMINE_TYPE` on all-null columns

**Symptom:** `PySparkValueError: [CANNOT_DETERMINE_TYPE]` when creating a DataFrame where a column (e.g. `staff_role.valid_to`) was `None` in every sample row.

**Cause:** Spark's schema inference from Python objects can't infer a type with zero non-null samples to look at.

**Fix:** Provide explicit `StructType`/`StructField` schemas whenever a table has nullable or potentially all-null columns (`valid_to`, `deleted_at`, etc.) — applied proactively to every table generated afterward.

### 3. Random seed not reproducible across individual cell re-runs

**Symptom:** Re-running a single cell (Cell 8, repair job generation) in isolation produced a different result than the first run.

**Cause:** `random.seed(42)` was called once at the top of the notebook. Python's `random` module holds one continuous stream for the whole kernel session — re-running only one cell resumes that stream from wherever it was left, not from the seed.

**Fix:** Call `random.seed(42)` at the top of every generation cell going forward, so each cell is independently reproducible. Confirmed with the user this is a synthetic-data-generation artifact only — real production pipelines don't have this problem, since they rely on `MERGE`/idempotency by natural key rather than replaying a random stream.

### 4. Missing `CLEANER` staff role

**Symptom:** Writing the cleaning step revealed no staff member held a `CLEANER` role.

**Cause:** Oversight in the initial staff/role seed data — a small-team business assumption (staff wearing multiple hats) wasn't reflected everywhere.

**Fix:** Added a `CLEANER` role assignment to an existing driver (`staff_id=3`), consistent with the "small team, multiple hats" business model already agreed on.

### 5. `TABLE_OR_VIEW_NOT_FOUND: silver.vehicle` across notebooks (multi-day)

**Symptom:** Notebook 02 couldn't see tables written by notebook 01, even after both were saved and re-run.

**Two wrong diagnoses, in order tried:**
- Assumed an embedded Derby metastore was scoped to the kernel's working directory — attempted to pin `javax.jdo.option.ConnectionURL`. Did not fix it.
- Assumed a Derby single-writer lock from two kernels running concurrently — had the user shut down notebook 01's kernel before running notebook 02. Did not fix it either.

**Real root cause:** `.enableHiveSupport()` was never called, so Spark used its default in-memory catalog. That catalog is scoped to a single JVM/kernel and never persists across notebooks — file paths and concurrency were never the issue, and Derby was never even in use.

**Actual fix:** Created `src/utils/lakehouse.py`, a small helper (`table_path`, `read_table`, `write_table`) that reads and writes Delta tables directly by filesystem path (`spark-warehouse/{layer}.db/{table}`) instead of through the Spark SQL catalog. A Delta table's own `_delta_log` is self-describing, so this works across any session. `spark_session.py` was updated to drop the now-irrelevant Derby config and document why Hive support is deliberately not enabled. Notebook 02 switched to the helper and worked immediately — no need to re-run notebook 01, since `saveAsTable` had already physically written the data at the standard path.

### 6. Rule-based extractor silently drops an ambiguous message

**Symptom:** The test message *"That Toyota from yesterday is looking good after the wash"* matched no keyword in `classify_event_type()` and fell through to `IGNORE` / auto-rejected, instead of being flagged `PENDING` for human review as intended.

**Cause:** Keyword-matching classification has no notion of "I'm not sure" — anything that doesn't match a known pattern is treated as a non-event rather than an edge case.

**Not fixed** (left as-is deliberately): flagged as a concrete illustration of why the Ops/DQ dashboard matters in the design — naive extractors, whether rule-based or LLM-based, can silently drop borderline cases without an explicit low-confidence path, and this is exactly what a review-queue backlog metric is meant to catch.

## Key architectural decisions

- **Docker over local install**: avoids Windows-specific Spark setup pain (`winutils.exe`, `JAVA_HOME`), and keeps the environment reproducible.
- **Path-based Delta access over a real metastore**: rather than standing up Derby/Postgres locally just to get named-table lookups working across notebooks, tables are read/written by file path via `lakehouse.py`. This sidesteps the problem entirely in local dev; on Databricks, Unity Catalog is a real always-on multi-session catalog, so named tables work there without any of this machinery — the local-only workaround doesn't carry forward.
- **Explicit schemas over inference**: any table with a nullable column gets an explicit `StructType`, avoiding a class of errors that only appears once null values are involved.
- **Funnel-based synthetic data, not fully independent rows**: the Silver layer models real attrition — not every vehicle reaches every stage (customs holds, blocked parts, failed re-inspections, sale installments), so downstream stage counts and profit figures reflect a believable funnel rather than a uniform pipeline.
- **`fact_profit` scope is explicit and limited**: cost currently covers purchase + repair only. Shipping, customs, and cleaning overhead are not yet in the model, since no Silver `expense` table exists yet — flagged as a known gap rather than silently baked into the margin numbers.
- **Rule-based classification as an LLM stand-in**: the WhatsApp and receipt agents use keyword matching and a simulated OCR error rate instead of a real LLM call, to prove out the Bronze → Silver → review-queue → Gold pattern without needing live model calls. The pattern (confidence scoring, gating into a review queue) is the same one a real LLM-backed version would use.

## Known gaps (not yet addressed)

- No Silver `expense` table — `fact_expense` doesn't exist, and `fact_profit`'s cost figure omits shipping, customs, and cleaning overhead.
- `dim_customer` is not built as SCD2 (accepted trade-off — customer name/phone changes aren't expected to need historical tracking for this project's purposes).
- The remaining five Phase 8 dashboards (Inventory, Workshop, Sales, Finance, Driver/Salesman Performance, Ops/DQ) are designed but not yet built as actual Power BI files — deferred until Power BI Desktop is installed.
