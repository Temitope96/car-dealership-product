# Supabase migration — context handoff

This file exists so a new chat can pick up the live-system migration without replaying the full history. Read this first.

## Where this came from

`car-dealership-product` (this repo) is a portfolio project: a Bronze/Silver/Gold lakehouse (Docker + PySpark + Delta Lake) simulating a real Nigerian used-car import dealership's data platform, plus two rule-based stand-ins for LLM agents (WhatsApp group ingestion, receipt/OCR intake). Full build chronology is in the private `car-dealership-planning` repo (`BUILD_LOG.md` + phase1-9 design docs).

## The decision just made

Two separate goals were getting conflated, so we split them:

1. **Portfolio artifact** — stays exactly as-is: local Docker/PySpark/Delta Lake build, because that's what demonstrates lakehouse engineering skill to employers. Not changing this.
2. **Live system** (if this were to actually run a real dealership) — needs a completely different, much smaller stack, because the real data volume (tens of vehicles/month) never justified Spark in the first place. Also, Databricks Free Edition's terms explicitly prohibit commercial use, have no SLA, and cap jobs at 5 concurrent tasks — it's not viable for a live business even as a pilot.

Chosen live-system stack:
- **Capture layer**: Google Forms + the WhatsApp group workflow (already designed in `phase5a-google-forms.md` / `phase5b-5c-whatsapp-agents.md` in the planning repo) — unchanged, no app rollout needed for dealership staff.
- **System of record**: Supabase (managed Postgres), replacing Spark/Delta Lake. Same Bronze → Silver → Gold logic and the same star schema, just running as Postgres tables/views instead of Delta tables.
- **BI layer**: Power BI or Google Looker Studio (free), connected directly to Postgres.
- **Free tier + cron**: Supabase free tier pauses a project after ~7 days with no real database activity (not just a dashboard visit). Mitigation agreed: a daily GitHub Actions cron job pinging the database to keep it active, at zero cost, rather than paying for Pro ($25/mo) upfront. Revisit Pro once this is a real hands-off system someone depends on daily.

## What "migration" means here, concretely

Porting the existing design to Postgres:
- `sql/silver/001_create_silver_tables.sql` and `sql/gold/001_create_gold_tables.sql` (in this repo) are the DDL to adapt to Postgres syntax (mostly compatible — main watch-items are Spark-specific types, `MERGE` syntax differences, and identity/surrogate-key generation which Postgres handles natively via `GENERATED ALWAYS AS IDENTITY` rather than the manual surrogate-key helper used in the notebooks).
- `notebooks/02_build_gold_layer.ipynb` has the business logic (dimension builds, fact table joins, the `MERGE`/`UPDATE` operations for `dim_vehicle` SCD2 and listing status) — this logic needs to be re-expressed as plain SQL or a Python script using the Supabase client/`psycopg2`, not Spark.
- `notebooks/03_whatsapp_receipt_agents.ipynb` has the rule-based extraction/confidence-gating logic for the two agents — this can mostly move over as-is, just writing to Postgres tables instead of Delta paths.

## Suggested first steps for the new chat

1. Create the Supabase project (user does this — account/billing action).
2. Adapt the Silver DDL to Postgres syntax, table by table, starting with a small independent table (e.g. `branch` or `staff`) as a proof of concept before the full 26-table Silver layer.
3. Decide the connection pattern (direct `psycopg2`/SQLAlchemy from a script, vs. Supabase's REST/PostgREST API) for how the WhatsApp/receipt agents will write in production.
4. Set up the GitHub Actions daily keep-alive cron early, so the project never silently pauses mid-build.
5. Once Silver is ported, port Gold (star schema + fact tables), then point Power BI/Looker Studio at it.

## Repo locations (same for the new chat)

- Public repo: `car-dealership-product` (this folder) — runnable pipeline, notebooks, src, docker, sql, README.
- Private repo: `car-dealership-planning` — phase 1-9 design docs, `BUILD_LOG.md`, original master prompt.
- Both are on the user's machine under `ClaudeFiles/`, and pushed to GitHub under `Temitope96/`.
