"""
Telegram ingestion poller -- capture layer only.

Runs as a short-lived, scheduled process (see .github/workflows/telegram-poll.yml):
each invocation asks Telegram for whatever updates have arrived since the last
run, lands text messages in raw_message and photo messages in receipt_document,
then exits. It does NOT classify or extract anything -- that's still
src/pipelines/whatsapp_agent.py and src/pipelines/receipt_agent.py, run as
separate steps right after this one. This script's only job is capture.

Repurposes the existing whatsapp_group table rather than introducing a new
one: whatsapp_group_jid now holds a Telegram chat_id (as text) instead of a
WhatsApp group JID. A chat that hasn't been registered there is skipped --
that's a deliberate guardrail against a stray/unknown chat writing into the
pipeline, not a bug.

Requires one new table, telegram_poll_state (see sql/silver/002_telegram_poll_state.sql),
which stores the single last Telegram update_id this poller has already
consumed, so re-running never reprocesses old messages.

Group privacy mode is left ON (not disabled) -- staff must @-mention the bot
for it to see a message at all. The leading '@BotName' tag is stripped from
message_text before storage (see strip_bot_mention()) so it never pollutes
what the classification agent reads.

Env: TELEGRAM_BOT_TOKEN, SUPABASE_DB_URL (see .env.example).
Run directly: python -m src.pipelines.telegram_poller
"""

import json
import os
import socket
from datetime import datetime, timezone

import requests
import urllib3.util.connection as urllib3_cn
from sqlalchemy import text

from src.utils.db import get_pg_engine

# Some networks have a dead/blackholed IPv6 route to a server while IPv4
# works fine. Browsers and curl fail over to IPv4 quickly ("happy eyeballs");
# requests/urllib3 doesn't, so it can hang for the full connect-timeout on
# a broken IPv6 address before ever trying IPv4. Forcing IPv4-only DNS
# resolution for this process sidesteps that whole class of timeout.
urllib3_cn.allowed_gai_family = lambda: socket.AF_INET

API_ROOT = "https://api.telegram.org/bot{token}/{method}"
POLL_TIMEOUT_SECONDS = 10   # short poll -- this process exits right after, it does not stay connected
FETCH_LIMIT = 100


def get_token() -> str:
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not token:
        raise RuntimeError(
            "TELEGRAM_BOT_TOKEN is not set. Add it to your local .env for "
            "manual runs, and as a GitHub Actions secret for the scheduled "
            "workflow -- never commit it or paste it into chat."
        )
    return token


def api_call(token: str, method: str, **params) -> dict:
    resp = requests.get(API_ROOT.format(token=token, method=method), params=params, timeout=30)
    resp.raise_for_status()
    payload = resp.json()
    if not payload.get("ok"):
        raise RuntimeError(f"Telegram API error on {method}: {payload}")
    return payload["result"]


def get_last_offset(conn) -> int:
    row = conn.execute(text("SELECT last_update_id FROM telegram_poll_state WHERE id = 1")).first()
    if row is None:
        raise RuntimeError(
            "telegram_poll_state has no row. Run sql/silver/002_telegram_poll_state.sql "
            "in the Supabase SQL editor once before running this poller."
        )
    return row[0]


def set_last_offset(conn, update_id: int):
    conn.execute(
        text("UPDATE telegram_poll_state SET last_update_id = :uid, updated_at = now() WHERE id = 1"),
        {"uid": update_id},
    )


def load_group_map(conn) -> dict:
    """whatsapp_group_jid (Telegram chat_id, as text) -> group_id, for registered chats only."""
    rows = conn.execute(text(
        "SELECT group_id, whatsapp_group_jid FROM whatsapp_group WHERE is_active = true"
    )).mappings().all()
    return {r["whatsapp_group_jid"]: r["group_id"] for r in rows}


def sender_label(frm: dict) -> str:
    if not frm:
        return None
    if frm.get("username"):
        return f"@{frm['username']}"
    return f"tg:{frm.get('id')}"


def to_naive_utc(unix_ts: int) -> datetime:
    return datetime.fromtimestamp(unix_ts, tz=timezone.utc).replace(tzinfo=None)


def resolve_file_url(token: str, file_id: str) -> str:
    file_info = api_call(token, "getFile", file_id=file_id)
    return f"https://api.telegram.org/file/bot{token}/{file_info['file_path']}"


def strip_bot_mention(text_body: str, bot_username: str) -> str:
    """Drop a leading '@BotName' tag (privacy mode is on, so staff have to
    tag the bot for every message) so what lands in raw_message.message_text
    is the actual content, not the tag. Only strips a LEADING mention --
    '@BotName picked up the Camry' -> 'picked up the Camry'. A mention
    elsewhere in the sentence is left alone. Telegram usernames are always
    plain ASCII, so this is a simple case-insensitive prefix check, no
    entity-offset math needed."""
    if not text_body or not bot_username:
        return text_body
    mention = f"@{bot_username}"
    stripped = text_body.strip()
    if stripped.lower().startswith(mention.lower()):
        stripped = stripped[len(mention):].lstrip(" :,-–—")
    return stripped


def process_update(conn, token: str, update: dict, group_map: dict, bot_username: str) -> str:
    """Returns one of: 'message', 'receipt', 'skipped' -- for the run summary."""
    msg = update.get("message") or update.get("edited_message")
    if not msg:
        return "skipped"  # not a message update (e.g. a chat_member/join event)

    chat = msg.get("chat", {})
    if chat.get("type") not in ("group", "supergroup"):
        return "skipped"  # ignore private DMs to the bot -- this is a group-workflow pipeline

    frm = msg.get("from", {})
    if frm.get("is_bot"):
        return "skipped"  # never ingest another bot's messages

    chat_id = str(chat.get("id"))
    group_id = group_map.get(chat_id)
    if group_id is None:
        return "skipped"  # unregistered chat -- see load_group_map() docstring

    natural_key = f"tg-{chat_id}-{msg['message_id']}"
    sent_at = to_naive_utc(msg["date"])

    if "photo" in msg:
        largest = max(msg["photo"], key=lambda p: p.get("file_size", 0))
        file_url = resolve_file_url(token, largest["file_id"])
        conn.execute(text("""
            INSERT INTO receipt_document (whatsapp_message_id, sender_phone, sent_at, file_url)
            VALUES (:mid, :sender, :sent_at, :file_url)
            ON CONFLICT (whatsapp_message_id) DO NOTHING
        """), {
            "mid": natural_key, "sender": sender_label(frm),
            "sent_at": sent_at, "file_url": file_url,
        })
        return "receipt"

    text_body = msg.get("text") or msg.get("caption")
    if not text_body:
        return "skipped"  # e.g. a sticker, location pin, or other unhandled message type

    text_body = strip_bot_mention(text_body, bot_username)
    if not text_body:
        return "skipped"  # message was just the tag, nothing left to classify

    conn.execute(text("""
        INSERT INTO raw_message (group_id, whatsapp_message_id, sender_phone, sent_at, message_text, media_urls, raw_payload)
        VALUES (:group_id, :mid, :sender, :sent_at, :text, :media, CAST(:payload AS jsonb))
        ON CONFLICT (whatsapp_message_id) DO NOTHING
    """), {
        "group_id": group_id, "mid": natural_key, "sender": sender_label(frm),
        "sent_at": sent_at, "text": text_body, "media": None,
        "payload": json.dumps(update),
    })
    return "message"


def run():
    token = get_token()
    engine = get_pg_engine()
    bot_username = api_call(token, "getMe")["username"]

    with engine.begin() as conn:
        offset = get_last_offset(conn)
        group_map = load_group_map(conn)

    updates = api_call(token, "getUpdates", offset=offset + 1, limit=FETCH_LIMIT, timeout=POLL_TIMEOUT_SECONDS)

    if not updates:
        print("No new Telegram updates.")
        return

    counts = {"message": 0, "receipt": 0, "skipped": 0}
    max_update_id = offset

    with engine.begin() as conn:
        for update in updates:
            outcome = process_update(conn, token, update, group_map, bot_username)
            counts[outcome] += 1
            max_update_id = max(max_update_id, update["update_id"])
        # advance the offset past every update we saw this run, even skipped
        # ones -- otherwise Telegram keeps resending them on every poll.
        set_last_offset(conn, max_update_id)

    print(f"Fetched {len(updates)} update(s): {counts['message']} message(s), "
          f"{counts['receipt']} receipt(s), {counts['skipped']} skipped. "
          f"Offset advanced to {max_update_id}.")


if __name__ == "__main__":
    run()
