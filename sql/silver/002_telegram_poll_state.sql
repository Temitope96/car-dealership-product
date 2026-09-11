-- =====================================================================
-- Telegram poller state -- one row, tracks the last Telegram update_id
-- this pipeline has already consumed, so the scheduled poller never
-- reprocesses old messages. Run this once in the Supabase SQL editor.
-- =====================================================================

CREATE TABLE telegram_poll_state (
    id              SMALLINT PRIMARY KEY DEFAULT 1,
    last_update_id  BIGINT NOT NULL DEFAULT 0,
    updated_at      TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT telegram_poll_state_single_row CHECK (id = 1)
);

INSERT INTO telegram_poll_state (id, last_update_id) VALUES (1, 0);

-- ---------------------------------------------------------------------
-- Register the Telegram group chat that replaces the WhatsApp group.
-- whatsapp_group is being repurposed as-is (not renamed) -- its jid
-- column now holds a Telegram chat_id (as text) instead of a WhatsApp
-- group JID. Run this once you have the real chat_id (see the setup
-- walkthrough for how to find it -- it's a negative number for groups,
-- e.g. -1001234567890).
-- ---------------------------------------------------------------------

-- INSERT INTO whatsapp_group (branch_id, whatsapp_group_jid, name, is_active)
-- VALUES (1, 'PASTE_TELEGRAM_CHAT_ID_HERE', 'Ops Updates (Telegram)', true);
