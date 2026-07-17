# Dealership Data Platform — Nigerian Used-Car Import Business

An end-to-end data engineering project: a Bronze/Silver/Gold lakehouse for a Nigerian used-car import dealership, with two LLM-powered agents that turn the dealer's existing WhatsApp workflow (a staff group for status updates, a dedicated number for purchase receipts) into structured, queryable data — no app rollout required for the dealer's staff.

Built as a portfolio project: designed as if for production, developed locally in Docker/PySpark, and structured so every notebook and SQL script here can be lifted into Databricks with minimal changes.

## Why this project exists

Small import/used-vehicle dealers in Nigeria typically run the entire purchase-to-sale process through a WhatsApp group and a stack of Google Forms/Sheets. That's not a data problem to "fix" by replacing their workflow — it's a data engineering problem: capture what they already do, conform it into a real warehouse, and give the owner dashboards and alerts that didn't exist before.

## Project status

This repo is being built in public, phase by phase. Current state: **design complete, environment scaffolded, pipeline code in progress.**

| Stage | Status |
|---|---|
| Business workflow mapping | Done |
| Entity model | Done |
| Normalized (3NF) schema | Done |
| Star schema (Gold layer) | Done |
| Google Forms + WhatsApp agent specs | Done |
| ETL/ELT architecture | Done |
| Automation design | Done |
| Power BI dashboard design | Done |
| Local dev environment (this commit) | Done |
| Bronze ingestion notebook | In progress |
| Silver conformance notebook | Not started |
| Gold aggregation notebook | Not started |
| Databricks migration | Not started |

## Design documentation

All design work lives at the repo root as numbered phase documents — read them in order for the full reasoning, not just the artifacts:

1. [`phase1-workflow-design.md`](phase1-workflow-design.md) + [`phase1-swimlane.mermaid`](phase1-swimlane.mermaid) — the 11-step business process, actors, exceptions, SLAs
2. [`phase2-entity-identification.md`](phase2-entity-identification.md) — every business entity, including the WhatsApp-agent-driven ones
3. [`phase3-normalized-schema.sql`](phase3-normalized-schema.sql) + [`phase3-schema-notes.md`](phase3-schema-notes.md) — 3NF schema with rationale
4. [`phase4-star-schema.sql`](phase4-star-schema.sql) — dimensional model for reporting
5. [`phase5a-google-forms.md`](phase5a-google-forms.md), [`phase5b-5c-whatsapp-agents.md`](phase5b-5c-whatsapp-agents.md) — every data capture source, including the two WhatsApp agents
6. [`phase6-etl-architecture.md`](phase6-etl-architecture.md) — Bronze/Silver/Gold, incremental loading, CDC, error handling
7. [`phase7-automation.md`](phase7-automation.md) — scheduling, DQ checks, alerts
8. [`phase8-powerbi-dashboards.md`](phase8-powerbi-dashboards.md) — six dashboards, including an Ops/Data-Quality one
9. [`phase9-advanced-features.md`](phase9-advanced-features.md) — predictive analytics, anomaly detection, a WhatsApp query bot

[`dealership-data-platform-master-prompt.md`](dealership-data-platform-master-prompt.md) is the original brief this whole project was scoped from.

## Repo layout

```
.
├── phase1-...9-*.md/.sql       # design docs (see above)
├── sql/
│   ├── bronze/                 # raw landing tables (created by ingestion code, not static DDL)
│   ├── silver/                 # conformed entity schema (copy of Phase 3 DDL)
│   └── gold/                   # star schema (copy of Phase 4 DDL)
├── notebooks/                  # Jupyter notebooks — the actual pipeline, built incrementally
├── src/
│   ├── pipelines/               # reusable PySpark transformation logic
│   └── utils/                   # SparkSession setup, synthetic data generators, etc.
├── data/sample/                 # synthetic sample data only — never real dealer data
├── docker/
│   ├── Dockerfile
│   └── docker-compose.yml
└── .devcontainer/
    └── devcontainer.json        # VS Code "Reopen in Container" support
```

## Running this locally

You'll need [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed. Two ways to run it, pick whichever fits your VS Code setup:

**Option A — VS Code Dev Containers (recommended)**
1. Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) in VS Code.
2. Open this folder in VS Code, then Command Palette → **Dev Containers: Reopen in Container**.
3. VS Code builds the image and opens the project inside it — the Python/Jupyter extensions and PySpark are all ready, no separate browser step needed.

**Option B — docker compose (works with any editor)**
```bash
cd docker
docker compose up --build
```
Then open `http://localhost:8888/?token=devtoken` in a browser, or point VS Code's Jupyter extension at that same URL as a remote kernel.

Either way, verify the environment with this in a new notebook cell:

```python
from pyspark.sql import SparkSession
from delta import configure_spark_with_delta_pip

builder = (
    SparkSession.builder.appName("dealership-platform")
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
    .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")
)
spark = configure_spark_with_delta_pip(builder).getOrCreate()
spark.sql("SELECT 'Spark + Delta Lake are working' AS status").show(truncate=False)
```

If that prints the status row, the environment is good.

### If Docker Desktop isn't available

PySpark can be installed natively (`pip install pyspark==4.1.0 delta-spark==4.1.0`), but on Windows this also requires a matching JDK (17) on `JAVA_HOME` and `winutils.exe` on `PATH` for Hadoop's local filesystem shim — this is the exact pain Docker exists to avoid. If you go this route, the [Apache Spark Windows setup guide](https://spark.apache.org/docs/latest/) and the `winutils` releases matching your Hadoop version are the two things you'll need beyond `pip install`.

## Local dev → Databricks

Everything here is written to port over directly:

- `sql/silver/001_create_silver_tables.sql` and `sql/gold/001_create_gold_tables.sql` run as-is in a Databricks SQL editor (Unity Catalog managed tables) — the ANSI SQL used here doesn't rely on anything Postgres/local-only.
- Notebooks use plain `spark.sql(...)` and DataFrame API calls, no local-only constructs — moving a notebook to Databricks is a copy-paste, not a rewrite.
- The one thing that **does** change: local Delta tables live on the container filesystem (`spark-warehouse/`, gitignored); in Databricks they become Unity Catalog managed tables under `dealership_dev.bronze/silver/gold`. That swap happens by changing the catalog/schema referenced in each notebook's config cell, not the SQL itself.

## A note on data

There is no real dealer data in this repo, and there won't be — `data/sample/` contains only synthetic data generated with `faker`, built to match the shapes in the Phase 2/3 schema (realistic-looking VINs, Nigerian names/phone numbers, plausible auction prices) so the pipeline has something to run against before a real dealer relationship exists.
