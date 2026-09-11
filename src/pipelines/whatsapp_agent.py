"""
WhatsApp group ingestion agent -- productionized version.

Rule-based stand-in for an LLM extraction step (see BUILD_LOG.md for why
keyword matching was chosen for the portfolio build, and its documented
gap with ambiguous phrasing -- that gap is intentionally left in place
here too, not silently patched, so the review-queue backlog metric still
means something). Reads new rows from raw_message, classifies them,
matches them to a vehicle where possible, and writes results to
extracted_event, routing anything below the auto-accept threshold to
review_task.

Idempotent: only processes raw_message rows that don't already have a
matching extracted_event row, so it's safe to run this repeatedly --
on a schedule, or triggered by a new inbound message -- without
creating duplicates.

Run directly: python -m src.pipelines.whatsapp_agent
"""

import json

from sqlalchemy import text

from src.utils.db import get_pg_engine

AUTO_ACCEPT_THRESHOLD = 0.85
DEFAULT_REVIEWER_STAFF_ID = 1  # owner -- same default the local build used


def classify_event_type(message_text: str) -> str:
    t = message_text.lower()
    if "picked up" in t or "picking up" in t:
        return "PICKUP"
    if "arrived" in t or "at the office" in t:
        return "OFFICE_ARRIVAL"
    if "fixed" in t or "bumper" in t or "headlight" in t or "repair" in t or "working on" in t:
        return "REPAIR_PROGRESS"
    if "held" in t or "duty" in t or "customs" in t:
        return "CUSTOMS_UPDATE"
    return "IGNORE"


def match_vehicle(message_text: str, open_vehicles: list[dict]):
    """(vehicle_id, confidence) -- exact lot number > unique make+model
    mention > no match, same three-tier logic as the local build."""
    for v in open_vehicles:
        if v["auction_lot_no"] and v["auction_lot_no"] in message_text:
            return v["vehicle_id"], 0.95

    candidates = [
        v for v in open_vehicles
        if v["make"] and v["model"]
        and v["make"].lower() in message_text.lower()
        and v["model"].lower() in message_text.lower()
    ]
    if len(candidates) == 1:
        return candidates[0]["vehicle_id"], 0.60
    if len(candidates) > 1:
        return None, 0.35
    return None, 0.30


def extract(message_text: str, open_vehicles: list[dict]):
    event_type = classify_event_type(message_text)
    if event_type == "IGNORE":
        return event_type, None, 0.10
    vehicle_id, confidence = match_vehicle(message_text, open_vehicles)
    return event_type, vehicle_id, confidence


def run():
    engine = get_pg_engine()

    with engine.begin() as conn:
        open_vehicles = [
            dict(row) for row in conn.execute(text(
                "SELECT vehicle_id, auction_lot_no, make, model FROM vehicle "
                "WHERE current_status NOT IN ('SOLD', 'CANCELLED')"
            )).mappings().all()
        ]
        new_messages = conn.execute(text(
            "SELECT message_id, message_text FROM raw_message "
            "WHERE message_id NOT IN (SELECT message_id FROM extracted_event)"
        )).mappings().all()

    if not new_messages:
        print("No new messages to process.")
        return

    processed = []
    with engine.begin() as conn:
        for m in new_messages:
            event_type, vehicle_id, confidence = extract(m["message_text"], open_vehicles)
            review_status = (
                "AUTO_ACCEPTED" if confidence >= AUTO_ACCEPT_THRESHOLD
                else "AUTO_REJECTED" if event_type == "IGNORE"
                else "PENDING"
            )

            result = conn.execute(text("""
                INSERT INTO extracted_event
                    (message_id, vehicle_id, event_type, extracted_fields, confidence_score, review_status)
                VALUES
                    (:message_id, :vehicle_id, :event_type, CAST(:extracted_fields AS jsonb), :confidence_score, :review_status)
                RETURNING event_id
            """), {
                "message_id": m["message_id"],
                "vehicle_id": vehicle_id,
                "event_type": event_type,
                "extracted_fields": json.dumps({"raw_text": m["message_text"]}),
                "confidence_score": confidence,
                "review_status": review_status,
            })
            event_id = result.scalar_one()

            if review_status == "PENDING":
                conn.execute(text("""
                    INSERT INTO review_task (source_type, source_id, assigned_to_staff_id, status)
                    VALUES ('EXTRACTED_EVENT', :source_id, :staff_id, 'OPEN')
                """), {"source_id": event_id, "staff_id": DEFAULT_REVIEWER_STAFF_ID})

            processed.append((event_id, event_type, confidence, review_status))

    print(f"Processed {len(processed)} new message(s):")
    for event_id, event_type, confidence, review_status in processed:
        print(f"  event_id={event_id:<4} {event_type:<16} confidence={confidence:.2f}  {review_status}")


if __name__ == "__main__":
    run()
