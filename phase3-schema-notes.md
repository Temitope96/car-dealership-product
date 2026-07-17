# Phase 3 — Normalized Schema: Design Notes

Full DDL is in `phase3-normalized-schema.sql`. Key decisions:

**3NF, not star schema, at this layer.** This is the system-of-record shape — every fact stored once, joined by key. The star schema (Phase 4) is a derived reporting layer built from this, not a replacement for it.

**Surrogate keys everywhere**, natural keys (VIN, WhatsApp message id) kept as unique columns. This lets a vehicle exist in the system before its VIN is confirmed (common right after an auction win, before paperwork lands), and lets Delta `MERGE` in Phase 6 key off the natural id without coupling to the surrogate.

**`vehicle_stage_history` as an append-only log**, separate from `vehicle.current_stage`. Phase 1 established that a vehicle's stage is not strictly forward-moving (inspection↔repair loops, sale fall-through). A single mutable `current_stage` column would lose that history; the log makes "how long was this vehicle stuck at customs" and "how many repair cycles did it take" answerable later without extra work.

**Nullable `vehicle_id` on `extracted_event`, `extracted_receipt_line`, and `expense`.** A WhatsApp message or receipt often can't be matched to a vehicle at ingestion time (driver just says "car's here" with no VIN) — matching happens in Silver ETL. `expense.vehicle_id` is nullable for genuinely vehicle-agnostic costs (per your open assumption on overhead allocation — revisit once you confirm how those should be split).

**`review_task` as a single polymorphic queue** rather than two separate ones for messages vs. receipts. One operational surface for staff to clear backlog from, referenced by the Ops/DQ dashboard in Phase 8.

**Soft deletes, never hard deletes**, on every table that represents a real business event (`is_deleted` + `deleted_at`). Combined with `vehicle_stage_history` and full historical rows on `listing`/`sale` (fall-through creates a new row, doesn't overwrite), this is what gives Phase 6 clean CDC/merge semantics and what gives Phase 9 clean training data for predictive models later.

**`source_id` / `source_record_id` on every capturable table.** This is the single most load-bearing design choice in the whole schema — it's what lets Forms, the WhatsApp group agent, and the receipt agent all write to the *same* tables instead of parallel siloed ones, and it's what powers the "% of records from WhatsApp vs. Forms" data-quality KPI from Phase 4's `DimDataSource`.
