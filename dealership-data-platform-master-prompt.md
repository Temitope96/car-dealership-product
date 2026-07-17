# Master Prompt: Nigerian Used-Car Dealership Data Platform

Use this as a single prompt, or execute it phase by phase (each phase depends on the ones before it — do not skip ahead).

---

## Role

Act as a Principal Data Engineer, Solutions Architect, Data Warehouse Architect, BI Consultant, and Product Manager, combined. Design and build a production-grade data platform for a Nigerian used-car import dealership, and explain design decisions against data engineering best practices at each step. Assume the platform must scale to multiple branches later — no single-tenant assumptions in the schema or pipelines.

## Business Context

The dealer buys damaged/used vehicles at international auctions, imports them to Nigeria, repairs them, and resells them. Core workflow:

1. Purchase vehicle abroad
2. Ship to Nigeria
3. Vehicle arrives at port
4. Driver picks up vehicle from port
5. Vehicle arrives at office
6. Inspection
7. Repairs / parts replacement
8. Cleaning
9. Listed for sale
10. Sold
11. Profit recorded

Two field realities that any design must accommodate, because they are the dealer's actual system of record today:

- **WhatsApp group updates.** Staff post vehicle status updates (port arrival, pickup, delivery, inspection notes, repair progress, etc.) into a WhatsApp group in free text, as events happen.
- **Purchase receipts via WhatsApp.** Dealers send photos/PDFs of purchase receipts to a dedicated business WhatsApp number.

Both are unstructured or semi-structured inputs that must land in the same warehouse as the structured Google Forms data. Batch processing is preferred over real-time for both — freshness of a few hours is acceptable and far cheaper/more reliable than streaming.

## Objectives

Accurate record keeping, automation, data validation, incremental updates, insert/update/delete (CDC) handling, historical tracking (SCD), reporting, KPI monitoring, executive dashboards, predictive analytics.

## Preferred Stack (recommend alternatives where better)

- Lakehouse: Databricks, Delta Lake, Unity Catalog
- Languages: Python, SQL
- Structured capture: Google Forms, Google Sheets, Google Apps Script
- BI: Power BI
- **New, for the agent-based intake:**
  - WhatsApp ingestion: Meta WhatsApp Cloud API or a Business Solution Provider (Twilio, Gupshup, 360dialog) — needed to legally and reliably receive group/DM messages and media via webhook. Avoid unofficial libraries (e.g., Baileys) for anything production-facing; they violate WhatsApp ToS and will get numbers banned.
  - Document/OCR: Google Document AI, Azure AI Document Intelligence, or AWS Textract for receipt line-item extraction; a multimodal LLM (Claude/GPT vision) as a fallback or primary extractor for messy/handwritten receipts, with confidence scoring.
  - Message parsing: LLM-based structured extraction (function calling / JSON mode) to turn free-text WhatsApp updates into typed events, with a confidence score and a human review queue for low-confidence extractions.

---

## Phase 1 — Business Workflow Design (foundation, no dependencies)

Map the 11-step process end to end. For each step define: trigger, actor/role, inputs, outputs, systems of record (including "WhatsApp group message" and "WhatsApp receipt image" as legitimate systems of record), possible exceptions/rework loops (e.g., vehicle fails inspection twice, sale falls through), and SLA/expected duration. Produce a swimlane diagram (driver, inspector, workshop, sales, finance, dealer-owner).

## Phase 2 — Entity Identification (depends on Phase 1)

From the workflow, extract every business entity, e.g.: Vehicle, Auction, Purchase, Shipment, Port Clearance, Driver, Trip/Pickup, Inspection, Damage Item, Repair Job, Part, Vendor, Cleaning Task, Listing, Sale, Customer, Payment, Expense, Branch, Staff/Role. Also define two new entity families driven by the WhatsApp agents:

- **Raw Message** (WhatsApp group text/media, sender, timestamp, group id) and **Extracted Event** (parsed status update linked to a Vehicle, with confidence + review status)
- **Receipt Document** (raw image/PDF, sender, timestamp) and **Extracted Receipt Line** (vendor, amount, currency, date, auction lot/VIN reference, confidence + review status)

Every extracted entity must have a foreign key path back to Vehicle so agent-sourced data joins cleanly with form-sourced data.

## Phase 3 — Normalized Relational Schema / OLTP (depends on Phase 2)

3NF schema covering all entities above, with proper PKs/FKs, surrogate keys, audit columns (created_at, updated_at, source_system, source_record_id), and soft-delete flags. Include the raw message and receipt tables as first-class tables, not an afterthought bolted onto the vehicle table.

## Phase 4 — Star Schema for Reporting (depends on Phase 3)

Fact tables (e.g., FactPurchase, FactRepair, FactSale, FactExpense) and conformed dimensions (DimVehicle, DimDriver, DimDealer/Staff, DimVendor, DimBranch, DimDate, DimDataSource). DimDataSource matters here specifically to let dashboards filter/report on "% of records that came from WhatsApp vs. Forms vs. manual entry" — a useful data-quality KPI on its own.

## Phase 5 — Source Systems & Data Capture Design (depends on Phase 3/4, so fields map cleanly to entities)

**5a. Google Forms** — one form per capture point (Purchase, Port Arrival, Pickup, Inspection, Repair, Cleaning, Listing, Sale). For each: fields, validation rules, required fields, dropdown value lists (sourced from Sheets so they stay centrally managed), and which entity/table each field maps to.

**5b. WhatsApp Group Ingestion Agent** — webhook receives every group message; raw payload lands untouched in a bronze landing table/volume (text + media URLs, sender, timestamp, group id). A scheduled batch job (not real-time) runs an LLM extraction pass: classify message type (status update vs. chatter), extract structured fields, attach a confidence score, and match to a Vehicle via VIN/lot number/plate mentioned or fuzzy match on recent context. Below a confidence threshold, route to a human review queue instead of auto-committing.

**5c. Receipt Intake Agent** — dedicated WhatsApp number receives receipt images/PDFs from dealers. Raw file stored in blob/volume; OCR/document-AI or vision-LLM extracts vendor, amount, currency, date, and vehicle reference. Same confidence-threshold + review-queue pattern as 5b. Extracted amounts feed FactPurchase/FactExpense.

## Phase 6 — ETL/ELT & Lakehouse Architecture (depends on Phase 5 sources + Phase 4 targets)

- **Bronze**: raw, append-only, schema-on-read. Includes raw WhatsApp messages, raw receipt files, raw Form/Sheet exports.
- **Silver**: cleaned, deduped, typed, conformed to entities from Phase 3 — this is where LLM-extracted fields from 5b/5c get validated against reference data (does the VIN exist? does the driver exist?) before being trusted.
- **Gold**: star schema from Phase 4, ready for BI.
- Incremental loading via Delta Lake `MERGE` keyed on natural keys (VIN, receipt id, message id) for CDC/upserts; watermark-based incremental reads from Sheets/Forms exports and from the WhatsApp/receipt bronze tables.
- Error handling: dead-letter table for messages/receipts that fail extraction entirely; retry logic; alerting (Phase 7) when the review queue backlog grows past a threshold.

## Phase 7 — Automation (depends on Phase 6)

Scheduled batch cadence (e.g., WhatsApp/receipt extraction jobs every few hours; Forms/Sheets sync on a similar cadence — avoid real-time/streaming unless a concrete business case justifies the cost). Data quality checks (nulls, referential integrity, duplicate VIN/receipt detection). Missing-data alerts (e.g., vehicle stuck >48h with no inspection record). Notifications to staff/dealer via WhatsApp or email when review queues need attention. Power BI dataset refresh triggered after gold layer completes.

## Phase 8 — Power BI Dashboards (depends on Phase 6 gold layer)

Executive, Inventory, Workshop, Sales, Finance, and Driver/Salesman Performance dashboards, plus an **Operations/Data-Quality dashboard** to monitor the WhatsApp and receipt agents themselves (extraction confidence trends, review-queue backlog, % auto-matched vs. manually resolved) — without this, the agent pipelines will silently degrade and nobody will notice.

## Phase 9 — Advanced Features (depends on all prior phases)

Predictive repair-cost and profit-margin models per vehicle class/auction source; time-to-sale prediction; anomaly detection on receipts (price outliers, possible fraud) and on WhatsApp updates (vehicles with no activity beyond SLA); a WhatsApp query bot letting the dealer ask "how many cars are in the workshop" in natural language against the gold layer; expanding OCR to auction invoices and customs paperwork, not just purchase receipts.

---

Work through the phases in order — each output (schema, entity list, form spec) becomes an input contract for the next phase. Flag any assumption that needs the dealer's confirmation before proceeding (e.g., actual WhatsApp message volume/format, whether multiple branches already exist, expected receipt volume/day) rather than guessing.
