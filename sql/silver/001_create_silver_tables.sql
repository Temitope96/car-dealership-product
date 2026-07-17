-- =====================================================================
-- Phase 3 — Normalized Relational Schema (3NF / OLTP-style source model)
-- Nigerian Used-Car Dealership Data Platform
--
-- Notes:
--  * Written in ANSI/Postgres-flavored SQL. This is the *logical* source
--    model — Phase 6 maps each table to a Delta Lake Bronze/Silver table
--    (Unity Catalog managed tables), so column names here are the
--    contract the Silver layer conforms to.
--  * Every transactional table carries the same audit pattern:
--      created_at, updated_at        -> when the row was written/changed
--      source_id                     -> FK to data_source (Form/WhatsApp/Manual)
--      source_record_id              -> natural id in the source system
--                                        (Form response id, WhatsApp message id)
--      is_deleted, deleted_at        -> soft delete, never hard-delete
--  * PROFIT_RECORD is intentionally NOT in this file — it is a derived
--    Gold-layer fact (Phase 4/6), not an OLTP table.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Reference / Master Data
-- ---------------------------------------------------------------------

CREATE TABLE branch (
    branch_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    address         VARCHAR(255),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE data_source (
    source_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_code     VARCHAR(30) NOT NULL UNIQUE,   -- 'GOOGLE_FORM','WHATSAPP_GROUP_AGENT','RECEIPT_AGENT','MANUAL'
    description     VARCHAR(200)
);

CREATE TABLE staff (
    staff_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_id       BIGINT NOT NULL REFERENCES branch(branch_id),
    name            VARCHAR(120) NOT NULL,
    phone_whatsapp  VARCHAR(30),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE staff_role (
    staff_id        BIGINT NOT NULL REFERENCES staff(staff_id),
    role_code       VARCHAR(30) NOT NULL,  -- 'OWNER','DRIVER','INSPECTOR','MECHANIC','CLEANER','SALES','FINANCE'
    valid_from      DATE NOT NULL DEFAULT current_date,
    valid_to        DATE,                  -- NULL = currently active in this role
    PRIMARY KEY (staff_id, role_code, valid_from)
);

CREATE TABLE auction_house (
    auction_house_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name             VARCHAR(120) NOT NULL,
    country          VARCHAR(60),
    created_at       TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE vendor (
    vendor_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(120) NOT NULL,
    contact_phone   VARCHAR(30),
    contact_email   VARCHAR(120),
    created_at      TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE part (
    part_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(120) NOT NULL,
    category        VARCHAR(60),
    created_at      TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE inspection_checklist_item (
    item_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category        VARCHAR(60) NOT NULL,   -- 'ENGINE','BODY','ELECTRICAL','INTERIOR','TIRES', etc.
    label           VARCHAR(200) NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order      INT
);

-- ---------------------------------------------------------------------
-- 2. Vehicle Lifecycle
-- ---------------------------------------------------------------------

CREATE TABLE vehicle (
    vehicle_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vin             VARCHAR(32) UNIQUE,        -- nullable: may be unknown at initial purchase capture
    auction_lot_no  VARCHAR(60),
    make            VARCHAR(60),
    model           VARCHAR(60),
    model_year      INT,
    branch_id       BIGINT NOT NULL REFERENCES branch(branch_id),
    current_stage   VARCHAR(30) NOT NULL DEFAULT 'PURCHASED',
    current_status  VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE, ON_HOLD, SOLD, CANCELLED
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMP
);

-- Append-only log of every stage transition. This is how "current stage"
-- becomes derivable/auditable rather than a single mutable column that
-- loses history (directly addresses the rework-loop problem from Phase 1).
CREATE TABLE vehicle_stage_history (
    history_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id      BIGINT NOT NULL REFERENCES vehicle(vehicle_id),
    from_stage      VARCHAR(30),
    to_stage        VARCHAR(30) NOT NULL,
    changed_at      TIMESTAMP NOT NULL DEFAULT now(),
    source_id       BIGINT NOT NULL REFERENCES data_source(source_id),
    source_record_id VARCHAR(100)
);

CREATE TABLE purchase (
    purchase_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id      BIGINT NOT NULL REFERENCES vehicle(vehicle_id),
    auction_house_id BIGINT REFERENCES auction_house(auction_house_id),
    buyer_staff_id  BIGINT REFERENCES staff(staff_id),
    price_amount    NUMERIC(14,2) NOT NULL,
    price_currency  VARCHAR(3) NOT NULL DEFAULT 'USD',
    purchase_date   DATE NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'CONFIRMED',  -- CONFIRMED, CANCELLED
    source_id       BIGINT NOT NULL REFERENCES data_source(source_id),
    source_record_id VARCHAR(100),
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMP
);

CREATE TABLE shipment (
    shipment_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id      BIGINT NOT NULL REFERENCES vehicle(vehicle_id),
    carrier         VARCHAR(120),
    bill_of_lading_no VARCHAR(60),
    etd             DATE,
    eta             DATE,
    ata             DATE,
    status          VARCHAR(20) NOT NULL DEFAULT 'IN_TRANSIT',  -- IN_TRANSIT, ARRIVED, DELAYED, DAMAGED_CLAIM
    source_id       BIGINT NOT NULL REFERENCES data_source(source_id),
    source_record_id VARCHAR(100),
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMP
);

CREATE TABLE port_arrival (
    port_arrival_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id      BIGINT NOT NULL REFERENCES vehicle(vehicle_id),
    arrival_date    DATE NOT NULL,
    clearance_status VARCHAR(20) NOT NULL DEFAULT 'PENDING',  -- PENDING, ON_HOLD, CLEARED
    cleared_date    DATE,
    hold_reason     VARCHAR(255),
    source_id       BIGINT NOT NULL REFERENCES data_source(source_id),
    source_record_id VARCHAR(100),
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMP
);

CREATE TABLE pickup (
    pickup_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id      BIGINT NOT NULL REFERENCES vehicle(vehicle_id),
    driver_staff_id BIGINT REFERENCES staff(staff_id),
    pickup_date     DATE NOT NULL,
    odometer        INT,
    photo_url       VARCHAR(500),
    source_id       BIGINT NOT NULL REFERENCES data_source(source_id),
    source_record_id VARCHAR(100),
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMP
);

CREATE TABLE office_intake (
    intake_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id      BIGINT NOT NULL REFERENCES vehicle(vehicle_id),
    intake_date     DATE NOT NULL,
    source_id       BIGINT NOT NULL REFERENCES data_source(source_id),
    source_record_id VARCHAR(100),
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMP
);

-- ---------------------------------------------------------------------
-- 3. Inspection & Repair
-- ---------------------------------------------------------------------

CREATE TABLE inspection (
    inspection_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id      BIGINT NOT NULL REFERENCES vehicle(vehicle_id),
    inspector_staff_id BIGINT REFERENCES staff(staff_id),
    inspection_date DATE NOT NULL,
    overall_result  VARCHAR(10) NOT NULL,  -- PASS, FAIL
    round_no        INT NOT NULL DEFAULT 1,  -- supports the inspect<->repair loop
    source_id       BIGINT NOT NULL REFERENCES data_source(source_id),
    source_record_id VARCHAR(100),
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMP
);

CREATE TABLE inspection_result (
    result_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inspection_id   BIGINT NOT NULL REFERENCES inspection(inspection_id),
    item_id         BIGINT NOT NULL REFERENCES inspection_checklist_item(item_id),
    pass_fail       VARCHAR(10) NOT NULL,  -- PASS, FAIL, N/A
    notes           TEXT
);

CREATE TABLE damage_item (
    damage_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inspection_id   BIGINT NOT NULL REFERENCES inspection(inspection_id),
    part_id         BIGINT REFERENCES part(part_id),
    severity        VARCHAR(10) NOT NULL DEFAULT 'MEDIUM',  -- LOW, MEDIUM, HIGH
    description     TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE repair_job (
    repair_job_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id      BIGINT NOT NULL REFERENCES vehicle(vehicle_id),
    mechanic_staff_id BIGINT REFERENCES staff(staff_id),
    start_date      DATE,
    end_date        DATE,
    status          VARCHAR(20) NOT NULL DEFAULT 'OPEN',  -- OPEN, IN_PROGRESS, BLOCKED_PARTS, DONE
    source_id       BIGINT NOT NULL REFERENCES data_source(source_id),
    source_record_id VARCHAR(100),
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMP
);

-- Many-to-many bridge: a repair job can address multiple damage items.
CREATE TABLE repair_job_damage (
    repair_job_id   BIGINT NOT NULL REFERENCES repair_job(repair_job_id),
    damage_id       BIGINT NOT NULL REFERENCES damage_item(damage_id),
    PRIMARY KEY (repair_job_id, damage_id)
);

CREATE TABLE repair_job_part (
    line_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    repair_job_id   BIGINT NOT NULL REFERENCES repair_job(repair_job_id),
    part_id         BIGINT REFERENCES part(part_id),
    vendor_id       BIGINT REFERENCES vendor(vendor_id),
    qty             INT NOT NULL DEFAULT 1,
    unit_cost       NUMERIC(12,2) NOT NULL,
    currency        VARCHAR(3) NOT NULL DEFAULT 'NGN',
    created_at      TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE cleaning_task (
    cleaning_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id      BIGINT NOT NULL REFERENCES vehicle(vehicle_id),
    staff_id        BIGINT REFERENCES staff(staff_id),
    task_date       DATE NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'DONE',  -- DONE, REDO_REQUIRED
    source_id       BIGINT NOT NULL REFERENCES data_source(source_id),
    source_record_id VARCHAR(100),
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 4. Sales & Finance
-- ---------------------------------------------------------------------

CREATE TABLE listing (
    listing_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id      BIGINT NOT NULL REFERENCES vehicle(vehicle_id),
    price_amount    NUMERIC(14,2) NOT NULL,
    currency        VARCHAR(3) NOT NULL DEFAULT 'NGN',
    channel         VARCHAR(60),   -- 'SHOWROOM','ONLINE','SOCIAL'
    listed_date     DATE NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE, WITHDRAWN, SOLD
    source_id       BIGINT NOT NULL REFERENCES data_source(source_id),
    source_record_id VARCHAR(100),
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMP
);

CREATE TABLE customer (
    customer_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(120),
    phone           VARCHAR(30),
    address         VARCHAR(255),
    created_at      TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE sale (
    sale_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id      BIGINT NOT NULL REFERENCES vehicle(vehicle_id),
    listing_id      BIGINT REFERENCES listing(listing_id),
    customer_id     BIGINT REFERENCES customer(customer_id),
    salesperson_staff_id BIGINT REFERENCES staff(staff_id),
    agreed_price    NUMERIC(14,2) NOT NULL,
    currency        VARCHAR(3) NOT NULL DEFAULT 'NGN',
    sale_date       DATE NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'PENDING_PAYMENT',  -- PENDING_PAYMENT, FINALIZED, REVERSED
    source_id       BIGINT NOT NULL REFERENCES data_source(source_id),
    source_record_id VARCHAR(100),
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMP
);

CREATE TABLE payment (
    payment_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sale_id         BIGINT NOT NULL REFERENCES sale(sale_id),
    amount          NUMERIC(14,2) NOT NULL,
    currency        VARCHAR(3) NOT NULL DEFAULT 'NGN',
    method          VARCHAR(30),   -- 'BANK_TRANSFER','CASH','POS'
    payment_date    DATE NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE expense (
    expense_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id      BIGINT REFERENCES vehicle(vehicle_id),  -- nullable: overhead expenses
    category        VARCHAR(60) NOT NULL,  -- 'CUSTOMS','TRANSPORT','REPAIR','MISC'
    amount          NUMERIC(14,2) NOT NULL,
    currency        VARCHAR(3) NOT NULL DEFAULT 'NGN',
    expense_date    DATE NOT NULL,
    source_id       BIGINT NOT NULL REFERENCES data_source(source_id),
    source_record_id VARCHAR(100),
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMP
);

-- ---------------------------------------------------------------------
-- 5. Automated Intake — WhatsApp Agents
-- ---------------------------------------------------------------------

CREATE TABLE whatsapp_group (
    group_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_id       BIGINT REFERENCES branch(branch_id),
    whatsapp_group_jid VARCHAR(100) NOT NULL UNIQUE,
    name            VARCHAR(120),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE raw_message (
    message_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    group_id        BIGINT NOT NULL REFERENCES whatsapp_group(group_id),
    whatsapp_message_id VARCHAR(100) NOT NULL UNIQUE,  -- natural key from WhatsApp, used for MERGE/dedup
    sender_phone    VARCHAR(30),
    sent_at         TIMESTAMP NOT NULL,
    message_text    TEXT,
    media_urls      TEXT[],           -- array of media references (photos/docs)
    raw_payload     JSONB,            -- full webhook payload, for replay/debug
    ingested_at     TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE extracted_event (
    event_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    message_id      BIGINT NOT NULL REFERENCES raw_message(message_id),
    vehicle_id      BIGINT REFERENCES vehicle(vehicle_id),  -- nullable until matched
    event_type      VARCHAR(30),      -- 'PICKUP','OFFICE_ARRIVAL','REPAIR_PROGRESS','INSPECTION_NOTE', etc.
    extracted_fields JSONB NOT NULL,  -- structured LLM output
    confidence_score NUMERIC(4,3) NOT NULL,   -- 0.000–1.000
    review_status   VARCHAR(20) NOT NULL DEFAULT 'PENDING',  -- PENDING, AUTO_ACCEPTED, CONFIRMED, REJECTED
    reviewed_by_staff_id BIGINT REFERENCES staff(staff_id),
    reviewed_at     TIMESTAMP,
    created_at      TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE receipt_document (
    receipt_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    whatsapp_message_id VARCHAR(100) NOT NULL UNIQUE,
    sender_phone    VARCHAR(30),
    sent_at         TIMESTAMP NOT NULL,
    file_url        VARCHAR(500) NOT NULL,
    ingested_at     TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE extracted_receipt_line (
    line_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    receipt_id      BIGINT NOT NULL REFERENCES receipt_document(receipt_id),
    vehicle_id      BIGINT REFERENCES vehicle(vehicle_id),   -- nullable until matched
    vendor_text     VARCHAR(200),
    amount          NUMERIC(14,2),
    currency        VARCHAR(3),
    receipt_date    DATE,
    confidence_score NUMERIC(4,3) NOT NULL,
    review_status   VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    reviewed_by_staff_id BIGINT REFERENCES staff(staff_id),
    reviewed_at     TIMESTAMP,
    created_at      TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE review_task (
    task_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_type     VARCHAR(30) NOT NULL,  -- 'EXTRACTED_EVENT' | 'EXTRACTED_RECEIPT_LINE'
    source_id       BIGINT NOT NULL,       -- polymorphic FK, enforced in application/ETL layer
    assigned_to_staff_id BIGINT REFERENCES staff(staff_id),
    status          VARCHAR(20) NOT NULL DEFAULT 'OPEN',  -- OPEN, IN_PROGRESS, RESOLVED
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    resolved_at     TIMESTAMP
);

-- ---------------------------------------------------------------------
-- Helpful indexes for the incremental/CDC patterns used in Phase 6
-- ---------------------------------------------------------------------
CREATE INDEX idx_vehicle_updated_at ON vehicle(updated_at);
CREATE INDEX idx_raw_message_group_sent ON raw_message(group_id, sent_at);
CREATE INDEX idx_extracted_event_review ON extracted_event(review_status);
CREATE INDEX idx_extracted_receipt_review ON extracted_receipt_line(review_status);
CREATE INDEX idx_review_task_status ON review_task(status);
