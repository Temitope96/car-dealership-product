# Phase 8 — Power BI Dashboards

All dashboards share global filters: Branch, Date Range, Vehicle Make/Model. Every dashboard's data comes from `gold.*` — nothing queries Bronze/Silver directly, so numbers are always consistent across dashboards.

## 1. Executive Dashboard

**Audience:** owner. **Purpose:** the 30-second health check.

- KPI cards: total vehicles in pipeline, total profit (MTD/QTD/YTD), average margin %, average days purchase-to-sale.
- Trend: monthly profit and unit count, last 12 months (`fact_profit`, `dim_date`).
- Pipeline funnel: count of vehicles at each `current_stage` (`fact_vehicle_lifecycle`) — instantly shows where inventory is piling up.
- % of records auto-captured via WhatsApp vs. Forms vs. manual (`dim_data_source`) — a proxy for how much manual data-entry burden the team is actually carrying.

## 2. Inventory Dashboard

**Audience:** operations. **Purpose:** where is every vehicle, right now, and what's stuck.

- Table: every active vehicle, current stage, days in current stage, flagged if past SLA (conditional formatting off the alert thresholds from Phase 7).
- Aging analysis: distribution of `days_purchase_to_port`, `days_port_to_clearance`, etc. (`fact_vehicle_lifecycle`) — identifies which stage is the actual bottleneck, not just anecdotal.
- Customs-hold list: vehicles with `clearance_status = On Hold`, sorted by longest-held.

## 3. Workshop Dashboard

**Audience:** workshop/inspection team lead. **Purpose:** repair throughput and quality.

- Inspection pass rate (first-round vs. requiring rework) — `inspection.overall_result` by `round_no`.
- Average repair duration and cost per vehicle, by damage severity and by mechanic (`fact_repair`, `dim_staff`).
- Parts spend by vendor and by category (`fact_repair` × `dim_vendor`/`dim_part`) — surfaces if one vendor is consistently pricier.
- Open repair jobs older than SLA (feeds off the same alert as Phase 7).

## 4. Sales Dashboard

**Audience:** sales team/manager. **Purpose:** what's listed, what's selling, how fast.

- Active listings by channel and age (`fact_sale`, `listing` status).
- Time-to-sale distribution (`days_listed_to_sold`) by make/model — informs pricing/listing strategy.
- Conversion: listings created vs. sales finalized vs. reversed (fall-through rate) — a KPI that didn't exist before this platform.
- Revenue by channel (Showroom/Online/Social).

## 5. Finance Dashboard

**Audience:** finance/owner. **Purpose:** cost, revenue, and margin detail.

- Profit and margin % per vehicle, sortable/filterable (`fact_profit`).
- Cost breakdown per vehicle: purchase, shipping, customs, repair, cleaning, overhead allocation (`fact_purchase`, `fact_expense`, `fact_repair`).
- Payment status: outstanding balances on `PENDING_PAYMENT` sales (`payment` vs. `sale.agreed_price`).
- Profit revision log (`fact_profit_history`) — visibility into how/why a vehicle's profit changed after the fact.
- Currency exposure: purchases in USD/GBP vs. sales in NGN, with FX rate used (`fact_purchase.fx_rate_used`) — relevant given imports are foreign-currency-denominated and sales are naira.

## 6. Driver/Salesman Performance Dashboard

**Audience:** owner/managers. **Purpose:** individual accountability without turning it into surveillance.

- Driver: pickups completed, average pickup-to-office-arrival time, by driver (`dim_staff` role = Driver).
- Salesperson: units sold, average sale price vs. listed price, average time-to-sale, by salesperson.
- Mechanic: repair jobs completed, average duration, rework rate (vehicles that failed re-inspection after their repair).

Keep this one framed around trends and averages rather than a public leaderboard — useful for coaching conversations, less useful (and more likely to breed resentment) as a scoreboard everyone sees.

## 7. Operations / Data-Quality Dashboard

**Audience:** whoever administers the platform day to day. **Purpose:** is the automation actually working.

- Review queue backlog over time, by source type (WhatsApp group vs. receipts) (`fact_review_queue`).
- Average confidence score and resolution time, trended — degrading confidence over time is an early warning the LLM prompt or matching logic needs attention.
- Dead-letter row count, trended.
- % auto-accepted vs. manually resolved, by week — the single best indicator of whether the agents are earning their keep or just generating review work.

This dashboard is arguably the most important one to check daily for the first few months — everything else assumes the intake pipeline is healthy, and this is the only view that actually confirms it.
