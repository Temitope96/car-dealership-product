"""
Receipt intake agent -- productionized version.

No real OCR/vision service is wired up yet (see SUPABASE_MIGRATION.md
roadmap -- that's the "wire up real WhatsApp + receipt intake" phase,
a separate, larger step). Until it is, this agent does the one honest
thing it can: notice every new receipt_document, and route it to a
human review task. It deliberately never fabricates a vendor or amount
and presents it as real data -- ocr_extract() below is the seam where a
real OCR/vision API call goes; nothing else in this file needs to
change when that's added.

Idempotent: only processes receipt_document rows that don't already
have a matching extracted_receipt_line row.

Run directly: python -m src.pipelines.receipt_agent
"""

import random

from sqlalchemy import text

from src.utils.db import get_pg_engine

AUTO_ACCEPT_THRESHOLD = 0.85
DEFAULT_REVIEWER_STAFF_ID = 1


def ocr_extract(receipt: dict) -> dict:
    """
    Placeholder for a real OCR/vision call against receipt['file_url'].
    Deliberately returns no vendor/amount and a confidence that always
    falls below the auto-accept threshold -- a receipt should never be
    auto-accepted with a fabricated number just because a human hasn't
    looked at it yet.
    """
    return {
        "vendor_text": None,
        "amount": None,
        "currency": None,
        "receipt_date": None,
        "confidence_score": round(random.uniform(0.30, 0.60), 2),
    }


def run():
    engine = get_pg_engine()

    with engine.begin() as conn:
        new_receipts = conn.execute(text(
            "SELECT receipt_id, file_url FROM receipt_document "
            "WHERE receipt_id NOT IN (SELECT receipt_id FROM extracted_receipt_line)"
        )).mappings().all()

    if not new_receipts:
        print("No new receipts to process.")
        return

    processed = []
    with engine.begin() as conn:
        for r in new_receipts:
            extraction = ocr_extract(dict(r))
            review_status = (
                "AUTO_ACCEPTED" if extraction["confidence_score"] >= AUTO_ACCEPT_THRESHOLD
                else "PENDING"
            )

            result = conn.execute(text("""
                INSERT INTO extracted_receipt_line
                    (receipt_id, vendor_text, amount, currency, receipt_date, confidence_score, review_status)
                VALUES
                    (:receipt_id, :vendor_text, :amount, :currency, :receipt_date, :confidence_score, :review_status)
                RETURNING line_id
            """), {"receipt_id": r["receipt_id"], "review_status": review_status, **extraction})
            line_id = result.scalar_one()

            if review_status == "PENDING":
                conn.execute(text("""
                    INSERT INTO review_task (source_type, source_id, assigned_to_staff_id, status)
                    VALUES ('EXTRACTED_RECEIPT_LINE', :source_id, :staff_id, 'OPEN')
                """), {"source_id": line_id, "staff_id": DEFAULT_REVIEWER_STAFF_ID})

            processed.append((line_id, review_status))

    print(f"Processed {len(processed)} new receipt(s):")
    for line_id, review_status in processed:
        print(f"  line_id={line_id:<4} {review_status}")


if __name__ == "__main__":
    run()
