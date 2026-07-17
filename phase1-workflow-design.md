# Phase 1 — Business Workflow Design

## Roles assumed (flagged for confirmation — see bottom)

Owner/Purchasing Agent, Freight/Shipping Coordinator, Port Clearing Agent, Driver, Inspector, Workshop/Mechanic team, Cleaning crew, Sales team, Finance/Accounts. A small operation may collapse several of these into one or two people — the schema in later phases will treat them as roles, not fixed headcount, so this works either way.

## Workflow Table

| # | Step | Trigger | Actor(s) | Inputs | Outputs | System(s) of Record | Exceptions / Rework | SLA (placeholder — confirm) |
|---|------|---------|----------|--------|---------|---------------------|----------------------|------------------------------|
| 1 | Purchase vehicle abroad | Auction win / bid accepted | Owner / Purchasing Agent | Auction listing, bid, funds | Purchase record, receipt/invoice | **Receipt Intake Agent** (photo sent to dedicated WhatsApp number) | Purchase falls through post-bid (payment/title issue) → cancelled purchase, funds reconciliation | Same day |
| 2 | Ship to Nigeria | Purchase confirmed | Freight/Shipping Coordinator | Purchase record, shipping line booking | Bill of lading, shipment record | Google Form (Shipment) | Shipment delay, damage in transit → insurance claim sub-process | 20–45 days (ocean freight, route-dependent) |
| 3 | Vehicle arrives at port | Vessel docks | Port Clearing Agent | Bill of lading, customs docs | Port arrival record, clearance status | Google Form (Port Arrival) + **WhatsApp group** post | Customs hold (documentation, duty dispute) → clearance delay loop until resolved | 3–14 days customs clearance |
| 4 | Driver picks up vehicle from port | Clearance granted | Driver | Clearance certificate | Pickup record, odometer/photo | **WhatsApp group** post (driver) | Vehicle not roadworthy for pickup → tow arranged, delay logged | Same day as clearance |
| 5 | Vehicle arrives at office | Pickup complete | Driver | Vehicle, pickup record | Office intake record | **WhatsApp group** post + Google Form (Intake) | Vehicle diverted (sold in transit, wrong location) → rare exception, manual correction | Same day |
| 6 | Vehicle inspection | Intake logged | Inspector | Vehicle, intake record | Inspection report, damage list | Google Form (Inspection checklist) + **WhatsApp group** notes/photos | Fails inspection → routed to repair (step 7) and re-inspected after; may loop multiple times | 1–3 days |
| 7 | Repairs & parts replacement | Inspection flags damage | Workshop/Mechanic team | Damage list, parts | Repair job record, parts used, labor cost | Google Form (Repair Job) + **WhatsApp group** progress updates | Parts unavailable/backordered → delay sub-process; repair reveals further damage → additional repair cycle | 3–14 days, damage-dependent |
| 8 | Vehicle cleaning | Repairs signed off | Cleaning crew | Repaired vehicle | Clean, sale-ready vehicle | Google Form (Cleaning complete) | Re-clean if buyer/inspection flags issue | 1 day |
| 9 | Listed for sale | Cleaning complete | Sales team | Vehicle, cost basis | Listing (price, photos, channel) | Google Form (Listing) | Relisted if price/channel changes | Same day |
| 10 | Vehicle sold | Buyer commits | Sales team | Listing, buyer info | Sale record, agreed price | Google Form (Sale) | Sale falls through (financing, buyer backs out) → relisted (loop to step 9); partial payment → finance hold before "sold" is finalized | Varies — days to weeks on lot |
| 11 | Profit recorded | Sale finalized & payment settled | Finance / system | All cost + sale records | Profit/margin figure per vehicle | **Calculated in warehouse** (Gold layer), not manually captured | Cost corrections after the fact (late invoice, warranty claim) → requires historical/SCD tracking, not a hard delete | Automatic on sale settlement |

## Exception / Rework Loops (explicit)

1. **Inspection ↔ Repair loop**: a vehicle can bounce between steps 6 and 7 multiple times before passing. The data model must support N inspection records and N repair job records per vehicle, not a 1:1 assumption.
2. **Customs clearance delay**: step 3 can stall indefinitely pending documentation; needs a status field (not just a timestamp) so "stuck vehicles" are queryable for the missing-data alerts in Phase 7.
3. **Sale falls through**: step 10 can revert to step 9 (relisted). A vehicle's "current stage" must be derivable from its latest event, not assumed to move strictly forward.
4. **Post-sale cost correction**: profit (step 11) may need to be recalculated after a late-arriving invoice or warranty cost. This is the strongest argument for full historical tracking (SCD Type 2) rather than overwrite-in-place.

## Swimlane Diagram

See `phase1-swimlane.mermaid` (rendered separately). It shows the same 11 steps by actor lane, with the two WhatsApp agents shown as a parallel "system" lane that listens in on the Driver/Office/Workshop lanes without those staff doing anything extra — they just keep posting to the group the way they already do.

## Assumptions flagged for dealer confirmation

1. **Team structure** — is each role (driver, inspector, mechanic, cleaner, salesperson) a distinct person, or does one or two people wear multiple hats today? This affects whether "Actor" should be modeled as a role or tied to a specific staff record.
2. **SLA figures** — the durations above are reasonable industry placeholders, not measured data. Do you have rough numbers (or even gut-feel ranges) for port-to-office and office-to-sale timing?
3. **Inspection rigor** — is inspection currently a formal checklist, or an informal walk-around? This determines whether Phase 5's inspection form should be a detailed checklist or a simpler pass/fail + notes.
4. **Single branch today** — confirming this is one location right now (design scales to multiple branches later per your brief, but I want to model "Branch" as a real dimension from Phase 2 onward only if it's not overkill for day one).
5. **Common exceptions** — beyond what's listed, are there recurring problems worth modeling explicitly (e.g., disputes with the auction house, recurring customs issues with a specific vehicle type)?
