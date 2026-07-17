# Phase 9 — Advanced Features

Ordered roughly by how soon they become viable — the first few need only a handful of months of Gold-layer history; the later ones need real data volume.

## Predictive analytics

- **Repair cost & duration prediction**: given make/model/year/damage severity, predict expected repair cost and days, trained on `fact_repair` history. Flags a repair job as a cost outlier the moment it's opened, not after the fact.
- **Time-to-sale prediction**: given make/model/price/channel, predict days-to-sell — informs listing price at the point of listing rather than guessing.
- **Profit forecasting by auction source**: which auction houses/vehicle classes historically yield the best margin after all costs — feeds back into *purchasing* decisions, closing the loop from sales data back to what to buy next. This is the highest-leverage model here since it affects capital allocation, not just reporting.

## Anomaly detection

- **Receipt anomalies**: statistical outlier detection on `extracted_receipt_line` amounts vs. historical price for similar vehicles/auction houses — catches OCR errors and potential overbilling/fraud in the same pass.
- **Process anomalies**: vehicles whose stage durations deviate sharply from the norm (beyond the fixed SLA thresholds in Phase 7) — a statistical/ML version of the rule-based alerts, catching slow-drift problems fixed thresholds miss.
- **WhatsApp extraction drift**: a sudden drop in average confidence score or a spike in a specific `event_type`'s rejection rate — signals the LLM prompt needs retuning before it silently degrades data quality (ties directly into the Ops dashboard from Phase 8).

## Conversational / WhatsApp query bot

A bot on the same staff WhatsApp number (or a separate one) that answers natural-language questions against the Gold layer — "how many cars are in the workshop," "what's our profit this month," "which cars have been on the lot over 60 days." Same LLM infrastructure as the ingestion agents, just querying instead of extracting. Meets the team where they already are rather than asking them to open Power BI.

## Expanded OCR / document intelligence

- **Auction invoices and customs paperwork**: same OCR/vision-LLM pipeline as purchase receipts, extended to customs duty receipts and auction-house invoices — reduces the `expense` category's remaining manual entry.
- **Damage photo assessment**: computer vision over inspection/repair photos (already being taken for the pickup/inspection forms) to auto-flag likely damage severity, cross-checked against the inspector's manual checklist — not a replacement for human inspection, but a second opinion that catches missed items.

## Worth flagging

None of Phase 9 should be started before Phases 1–8 are live and stable for a few months — every model here trains on the very data this platform is only now starting to generate cleanly. Building predictive models on a few weeks of data (or on the messy pre-platform history) risks confidently-wrong outputs that are worse than no model at all.
