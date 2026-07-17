# Phase 7 — Automation

## Scheduled ingestion (Databricks Workflow, cron-driven)

| Job | Cadence | Depends on |
|---|---|---|
| Pull Forms/Sheets → Bronze | Every 2 hours, business hours | — |
| WhatsApp webhook → Bronze | Continuous (event-driven, not a scheduled job) | — |
| Webhook reconciliation check (catch any dropped webhook deliveries by polling the Cloud API for messages since the last known `whatsapp_message_id`) | Nightly | — |
| Extraction batch (LLM group messages, OCR/LLM receipts) | Every 4 hours | Ingest jobs |
| Bronze → Silver merges | Every 4 hours, right after extraction | Extraction batch |
| Silver → Gold merges (dims, facts) | Every 4 hours, right after Silver | Silver merges |
| `fact_vehicle_lifecycle` / `fact_profit` recompute | Every 4 hours, after Gold facts | Gold merges |
| Power BI dataset refresh (REST API trigger) | Immediately after recompute | Recompute job |

Every 4 hours during business hours is the recommended default cadence — matches the "few hours of freshness is fine" preference and keeps compute costs low; tightenable later without redesigning anything if the business ever needs it.

## Data quality checks

Beyond the referential-integrity/null/range checks enforced at Silver (Phase 6), a daily DQ job runs cross-table checks and logs results to `gold.dq_check_results` (check_name, table, rows_failed, run_at):

- Every `vehicle_id` referenced in a Silver table exists in `silver.vehicle`.
- Every `sale.status = FINALIZED` has at least one `payment` row summing to `agreed_price` (flags under/over-paid sales).
- Every `purchase` older than 48 hours has a matched `extracted_receipt_line` (flags missing receipts — see alerts below).
- `extracted_event` / `extracted_receipt_line` rows stuck in `review_status = PENDING` for more than 24 hours (backlog check).

## Duplicate detection

| Scenario | Detection method | Resolution |
|---|---|---|
| Same VIN entered via two different Forms/sources | Unique constraint on `vehicle.vin`, plus a nightly fuzzy match (Levenshtein distance ≤ 2) across recently created vehicles without a VIN yet, to catch typos before they become separate vehicle rows | Flag as `review_task`, category = "possible duplicate vehicle" — never auto-merges, since merging vehicle history is destructive |
| Same WhatsApp event reported by two staff | Two `extracted_event` rows, same `event_type` + matched `vehicle_id`, within a 1-hour window | Second one marked `review_status = SUPERSEDED`, not written to Silver again |
| Same receipt photographed/sent twice | File hash comparison on incoming media in `receipt_document` | Second one flagged `is_duplicate = true`, excluded from extraction |

## Missing-data alerts

Derived from `fact_vehicle_lifecycle` and Silver tables, evaluated by the daily DQ job, written to an `automation.alerts` table:

- Vehicle at `PORT_ARRIVAL` stage with `clearance_status != Cleared` for more than 14 days.
- Vehicle at `OFFICE_ARRIVAL` with no `inspection` row after 48 hours.
- `repair_job.status IN ('Open','In Progress')` for more than 14 days.
- `purchase` with no matched receipt after 48 hours.
- `listing.status = 'Active'` for more than 60 days (aging inventory).
- Review queue backlog above a configurable threshold (e.g., 15 open tasks).

## Notifications

Delivered via the same WhatsApp Business API used for ingestion (send a message to the owner/ops number) and/or email, triggered by: any scheduled job failure, dead-letter table growth beyond threshold, and every alert row created above. Keep the notification list short and role-scoped (e.g., customs delays go to whoever handles clearing, aging-inventory alerts go to sales) rather than one firehose to the owner — otherwise alerts get muted.

## Dashboard refresh

Recommended for v1: **Import mode** in Power BI, with the dataset refresh triggered via the Power BI REST API as the final task in the Databricks Workflow (guarantees the dashboard reflects a fully-completed Gold run, not a partial one). Direct Query / Databricks SQL Warehouse connection is a viable upgrade path later if near-real-time becomes a real requirement, but adds cost and query latency that Import mode avoids for a dataset this size.
