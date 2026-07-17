# Phase 5a — Google Forms Specification

Nine forms, one per capture point. Pickup and Office Intake are merged into one form since Phase 1 established they happen the same day and are both filled by the driver — fewer forms means fewer chances staff skip one.

**Shared pattern for every form:**
- A "Vehicle" field is never free text. It's a dropdown sourced from a named range in a linked Google Sheet (`Active_Vehicles`) showing `VIN / Lot No — Make Model (Year)`, kept current by an Apps Script trigger that pulls the active vehicle list from the warehouse each morning. This is what prevents the classic Forms failure mode of a typo'd VIN creating an orphan record.
- Every form has a hidden/prefilled `source_code = GOOGLE_FORM` and a `submitted_by` field (dropdown of active staff, same Sheet-sourced pattern) — this is what populates `source_id` / `source_record_id` in Phase 3.
- Google Forms itself can't do cross-field validation (e.g., "end date after start date") — flagged per form below where Apps Script post-submit validation is needed instead of native Forms validation.

---

## 1. Vehicle Purchase Form

| Field | Type | Required | Validation | Dropdown Values |
|---|---|---|---|---|
| Auction Lot Number | Short text | Yes | Regex: alphanumeric, 4–20 chars | — |
| VIN (if known) | Short text | No | 17-char VIN pattern when filled | — |
| Make | Dropdown | Yes | — | Toyota, Honda, Lexus, Ford, Nissan, Other |
| Model | Short text | Yes | — | — |
| Model Year | Short text | Yes | 4-digit number, 1990–current year | — |
| Auction House | Dropdown | Yes | — | sourced from `Auction_Houses` sheet |
| Purchase Price | Short text (number) | Yes | Positive number | — |
| Currency | Dropdown | Yes | — | USD, GBP, NGN |
| Purchase Date | Date | Yes | Not in the future | — |
| Buyer (Staff) | Dropdown | Yes | — | sourced from `Active_Staff` sheet |
| Branch | Dropdown | Yes | — | sourced from `Branches` sheet |
| Receipt attached via WhatsApp? | Dropdown | Yes | — | Yes / No — if "No", Apps Script flags a follow-up reminder |

**Maps to:** `vehicle` (insert if new VIN/lot), `purchase`. **Relationship:** creates the Vehicle row that every subsequent form's dropdown will reference.

---

## 2. Shipment Booking Form

| Field | Type | Required | Validation | Dropdown Values |
|---|---|---|---|---|
| Vehicle | Dropdown | Yes | must exist in `Active_Vehicles` | — |
| Carrier | Short text | Yes | — | — |
| Bill of Lading No. | Short text | No | — | — |
| ETD | Date | Yes | — | — |
| ETA | Date | Yes | Apps Script check: ETA > ETD | — |
| Branch | Dropdown | Yes | — | sourced from `Branches` sheet |

**Maps to:** `shipment`.

---

## 3. Port Arrival & Clearance Form

| Field | Type | Required | Validation | Dropdown Values |
|---|---|---|---|---|
| Vehicle | Dropdown | Yes | must exist | — |
| Arrival Date | Date | Yes | Not in the future | — |
| Clearance Status | Dropdown | Yes | — | Pending, On Hold, Cleared |
| Hold Reason | Short text | Conditional | Required if status = "On Hold" (Apps Script enforced) | — |
| Cleared Date | Date | Conditional | Required if status = "Cleared"; must be ≥ Arrival Date | — |

**Maps to:** `port_arrival`, appends `vehicle_stage_history` row.

---

## 4. Vehicle Pickup & Office Arrival Form

| Field | Type | Required | Validation | Dropdown Values |
|---|---|---|---|---|
| Vehicle | Dropdown | Yes | must exist, and clearance_status = Cleared (Apps Script cross-check against Sheet) | — |
| Driver | Dropdown | Yes | — | sourced from `Active_Staff` filtered to role = Driver |
| Pickup Date | Date | Yes | ≥ cleared_date | — |
| Odometer (km) | Short text (number) | No | Positive integer | — |
| Photo | File upload | Yes | image only | — |
| Office Arrival Date | Date | Yes | ≥ Pickup Date | — |

**Maps to:** `pickup`, `office_intake`, appends `vehicle_stage_history` twice (PICKED_UP, AT_OFFICE).

---

## 5. Inspection Form

| Field | Type | Required | Validation | Dropdown Values |
|---|---|---|---|---|
| Vehicle | Dropdown | Yes | must exist | — |
| Inspector | Dropdown | Yes | — | `Active_Staff` filtered to role = Inspector |
| Inspection Date | Date | Yes | Not in the future | — |
| Round No. | Short text (number) | Yes, auto-suggested | Apps Script pre-fills next round number for this vehicle | — |
| Checklist Section (repeated per item) | Grid: Pass / Fail / N/A + Notes | Yes per active item | driven by `inspection_checklist_item` table (synced to a Sheet) | Pass, Fail, N/A |
| Overall Result | Dropdown | Yes | must be Fail if any checklist item = Fail (Apps Script enforced) | Pass, Fail |
| Damage Items (if Fail) | Repeating section: Part, Severity, Description | Conditional | Required if Overall Result = Fail | Severity: Low, Medium, High |

**Maps to:** `inspection`, `inspection_result` (one row per checklist item), `damage_item`.

Note: Google Forms doesn't support true dynamic repeating sections well — in practice, either (a) a fixed checklist with one row per known item (recommended, since the list is a bounded, curated set from `inspection_checklist_item`), or (b) a linked Google Sheet for the damage-item detail entered directly by the inspector, with the Form only capturing the pass/fail summary. Recommend (a).

---

## 6. Repair Job Form

| Field | Type | Required | Validation | Dropdown Values |
|---|---|---|---|---|
| Vehicle | Dropdown | Yes | must exist | — |
| Mechanic | Dropdown | Yes | — | `Active_Staff` filtered to role = Mechanic |
| Related Damage Item(s) | Multi-select dropdown | No | sourced from open `damage_item` rows for this vehicle | — |
| Start Date | Date | Yes | — | — |
| End Date | Date | No | ≥ Start Date if filled | — |
| Status | Dropdown | Yes | — | Open, In Progress, Blocked (Parts), Done |
| Parts Used (repeating) | Part, Vendor, Qty, Unit Cost, Currency | Conditional | Required if Status = Done | Part/Vendor sourced from catalog sheets |

**Maps to:** `repair_job`, `repair_job_damage`, `repair_job_part`.

---

## 7. Cleaning Form

| Field | Type | Required | Validation | Dropdown Values |
|---|---|---|---|---|
| Vehicle | Dropdown | Yes | must exist, repair status = Done (Apps Script cross-check) | — |
| Staff | Dropdown | Yes | — | `Active_Staff` |
| Task Date | Date | Yes | — | — |
| Status | Dropdown | Yes | — | Done, Redo Required |

**Maps to:** `cleaning_task`.

---

## 8. Listing Form

| Field | Type | Required | Validation | Dropdown Values |
|---|---|---|---|---|
| Vehicle | Dropdown | Yes | must exist, cleaning status = Done | — |
| Price | Short text (number) | Yes | Positive number | — |
| Currency | Dropdown | Yes | — | NGN (default), USD |
| Channel | Dropdown | Yes | — | Showroom, Online, Social Media |
| Listed Date | Date | Yes | — | — |

**Maps to:** `listing`.

---

## 9. Sale Form

| Field | Type | Required | Validation | Dropdown Values |
|---|---|---|---|---|
| Vehicle | Dropdown | Yes | must be an active Listing | — |
| Customer Name | Short text | Yes | — | — |
| Customer Phone | Short text | No | Nigerian phone pattern | — |
| Salesperson | Dropdown | Yes | — | `Active_Staff` filtered to role = Sales |
| Agreed Price | Short text (number) | Yes | Positive number | — |
| Currency | Dropdown | Yes | — | NGN, USD |
| Sale Date | Date | Yes | — | — |
| Payment Status | Dropdown | Yes | — | Pending Payment, Fully Paid |
| Amount Paid (if partial) | Short text (number) | Conditional | Required if status = Pending Payment; ≤ Agreed Price | — |

**Maps to:** `sale`, `payment` (initial payment row if any amount entered). Sale falling through is **not** handled in this form — it's a separate short "Sale Reversal" form (status → Reversed, triggers vehicle relisting) kept deliberately rare/manual since it's an exception path, not routine data entry.

---

## Apps Script responsibilities (beyond native Forms validation)

Cross-field and cross-record checks Forms can't do natively: conditional-required fields, date-ordering checks, and "does this vehicle exist / is it in the right stage" lookups against the `Active_Vehicles` sheet. Also responsible for: writing each submission to a per-form Sheet tab (landing zone), stamping `source_record_id` = Form response ID, and triggering the Phase 6 batch ingestion job (or simply being polled by it on schedule).
