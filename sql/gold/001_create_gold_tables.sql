-- =====================================================================
-- Phase 4 — Star Schema for Reporting (Gold layer logical model)
-- Materializes as Delta tables in Unity Catalog in Phase 6.
-- =====================================================================

-- ---------------------------------------------------------------------
-- DIMENSIONS
-- ---------------------------------------------------------------------

CREATE TABLE dim_date (
    date_key        INT PRIMARY KEY,   -- yyyymmdd
    full_date       DATE NOT NULL,
    day_of_week     VARCHAR(10),
    week_of_year    INT,
    month_no        INT,
    month_name      VARCHAR(10),
    quarter         INT,
    year            INT,
    is_weekend      BOOLEAN
);

CREATE TABLE dim_branch (
    branch_key      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_id       BIGINT NOT NULL,   -- natural key from OLTP
    name            VARCHAR(100),
    is_active       BOOLEAN
);

-- SCD Type 2: tracks role/branch changes over time for staff.
CREATE TABLE dim_staff (
    staff_key       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    staff_id        BIGINT NOT NULL,   -- natural key
    name            VARCHAR(120),
    primary_role    VARCHAR(30),
    branch_id       BIGINT,
    effective_from  DATE NOT NULL,
    effective_to    DATE,              -- NULL = current
    is_current      BOOLEAN NOT NULL DEFAULT TRUE
);

-- SCD Type 2: tracks stage/status changes so historical reporting
-- ("how many vehicles were in repair last March") reflects the state
-- at that time, not today's state.
CREATE TABLE dim_vehicle (
    vehicle_key     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id      BIGINT NOT NULL,   -- natural key
    vin             VARCHAR(32),
    make            VARCHAR(60),
    model           VARCHAR(60),
    model_year      INT,
    branch_id       BIGINT,
    stage           VARCHAR(30),
    status          VARCHAR(30),
    effective_from  TIMESTAMP NOT NULL,
    effective_to    TIMESTAMP,
    is_current      BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE dim_auction_house (
    auction_house_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    auction_house_id  BIGINT NOT NULL,
    name              VARCHAR(120),
    country           VARCHAR(60)
);

CREATE TABLE dim_vendor (
    vendor_key      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vendor_id       BIGINT NOT NULL,
    name            VARCHAR(120)
);

CREATE TABLE dim_part (
    part_key        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    part_id         BIGINT NOT NULL,
    name            VARCHAR(120),
    category        VARCHAR(60)
);

CREATE TABLE dim_customer (
    customer_key    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id     BIGINT NOT NULL,
    name            VARCHAR(120),
    phone           VARCHAR(30)
);

CREATE TABLE dim_expense_category (
    category_key    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_code   VARCHAR(60) UNIQUE
);

CREATE TABLE dim_payment_method (
    method_key      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    method_code     VARCHAR(30) UNIQUE
);

-- Conformed across every fact table. Powers the single most requested
-- data-quality KPI: "what % of records came from WhatsApp vs. Forms vs.
-- manual entry", split by branch/date/entity type.
CREATE TABLE dim_data_source (
    source_key      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_code     VARCHAR(30) UNIQUE   -- GOOGLE_FORM, WHATSAPP_GROUP_AGENT, RECEIPT_AGENT, MANUAL
);

-- ---------------------------------------------------------------------
-- FACTS
-- ---------------------------------------------------------------------

-- Grain: one row per vehicle purchase.
CREATE TABLE fact_purchase (
    purchase_key    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_key     BIGINT NOT NULL REFERENCES dim_vehicle(vehicle_key),
    auction_house_key BIGINT REFERENCES dim_auction_house(auction_house_key),
    buyer_staff_key BIGINT REFERENCES dim_staff(staff_key),
    branch_key      BIGINT REFERENCES dim_branch(branch_key),
    purchase_date_key INT REFERENCES dim_date(date_key),
    source_key      BIGINT REFERENCES dim_data_source(source_key),
    price_amount_usd NUMERIC(14,2),
    price_amount_ngn NUMERIC(14,2),
    fx_rate_used    NUMERIC(10,4)
);

-- Grain: one row per repair-job-part line (rolls up to repair job / vehicle).
CREATE TABLE fact_repair (
    repair_line_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_key     BIGINT NOT NULL REFERENCES dim_vehicle(vehicle_key),
    mechanic_staff_key BIGINT REFERENCES dim_staff(staff_key),
    part_key        BIGINT REFERENCES dim_part(part_key),
    vendor_key      BIGINT REFERENCES dim_vendor(vendor_key),
    branch_key      BIGINT REFERENCES dim_branch(branch_key),
    repair_start_date_key INT REFERENCES dim_date(date_key),
    repair_end_date_key   INT REFERENCES dim_date(date_key),
    source_key      BIGINT REFERENCES dim_data_source(source_key),
    qty             INT,
    unit_cost_ngn   NUMERIC(12,2),
    line_cost_ngn   NUMERIC(14,2)
);

-- Grain: one row per finalized/reversed sale.
CREATE TABLE fact_sale (
    sale_key        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_key     BIGINT NOT NULL REFERENCES dim_vehicle(vehicle_key),
    customer_key    BIGINT REFERENCES dim_customer(customer_key),
    salesperson_staff_key BIGINT REFERENCES dim_staff(staff_key),
    branch_key      BIGINT REFERENCES dim_branch(branch_key),
    sale_date_key   INT REFERENCES dim_date(date_key),
    source_key      BIGINT REFERENCES dim_data_source(source_key),
    agreed_price_ngn NUMERIC(14,2),
    status          VARCHAR(20)   -- FINALIZED, REVERSED (kept, not deleted)
);

-- Grain: one row per expense (includes shipping/customs/misc.).
CREATE TABLE fact_expense (
    expense_key     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_key     BIGINT REFERENCES dim_vehicle(vehicle_key),  -- nullable: overhead
    category_key    BIGINT REFERENCES dim_expense_category(category_key),
    branch_key      BIGINT REFERENCES dim_branch(branch_key),
    expense_date_key INT REFERENCES dim_date(date_key),
    source_key      BIGINT REFERENCES dim_data_source(source_key),
    amount_ngn      NUMERIC(14,2)
);

-- Grain: one row per vehicle (ACCUMULATING SNAPSHOT — updated in place
-- as milestones happen, unlike the append-only facts above). This is
-- the primary driver of Inventory/Workshop KPI dashboards (Phase 8):
-- time-in-stage, bottleneck identification, SLA breach detection.
CREATE TABLE fact_vehicle_lifecycle (
    vehicle_key             BIGINT PRIMARY KEY REFERENCES dim_vehicle(vehicle_key),
    purchase_date_key       INT REFERENCES dim_date(date_key),
    ship_date_key           INT REFERENCES dim_date(date_key),
    port_arrival_date_key   INT REFERENCES dim_date(date_key),
    cleared_date_key        INT REFERENCES dim_date(date_key),
    pickup_date_key         INT REFERENCES dim_date(date_key),
    office_intake_date_key  INT REFERENCES dim_date(date_key),
    first_inspection_date_key INT REFERENCES dim_date(date_key),
    inspection_pass_date_key  INT REFERENCES dim_date(date_key),
    inspection_rounds_count INT,
    repair_start_date_key   INT REFERENCES dim_date(date_key),
    repair_end_date_key     INT REFERENCES dim_date(date_key),
    cleaning_complete_date_key INT REFERENCES dim_date(date_key),
    listed_date_key         INT REFERENCES dim_date(date_key),
    sold_date_key           INT REFERENCES dim_date(date_key),
    days_purchase_to_port   INT,
    days_port_to_clearance  INT,
    days_clearance_to_pickup INT,
    days_pickup_to_intake   INT,
    days_intake_to_inspection INT,
    days_inspection_to_repair_complete INT,
    days_repair_to_cleaning INT,
    days_cleaning_to_listed INT,
    days_listed_to_sold     INT,
    total_days_purchase_to_sale INT,
    current_stage           VARCHAR(30),
    last_updated_at         TIMESTAMP
);

-- Grain: one row per vehicle, recalculated (not append-only — the one
-- deliberate exception in this model, because late-arriving costs must
-- revise profit after the fact per the Phase 1 exception).
CREATE TABLE fact_profit (
    vehicle_key     BIGINT PRIMARY KEY REFERENCES dim_vehicle(vehicle_key),
    total_cost_ngn  NUMERIC(14,2),
    total_revenue_ngn NUMERIC(14,2),
    profit_ngn      NUMERIC(14,2),
    margin_pct      NUMERIC(6,2),
    calculated_at   TIMESTAMP
);

-- Audit trail for fact_profit recalculations (append-only), so "why did
-- this vehicle's profit change" is always answerable.
CREATE TABLE fact_profit_history (
    profit_history_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_key     BIGINT NOT NULL REFERENCES dim_vehicle(vehicle_key),
    total_cost_ngn  NUMERIC(14,2),
    total_revenue_ngn NUMERIC(14,2),
    profit_ngn      NUMERIC(14,2),
    margin_pct      NUMERIC(6,2),
    calculated_at   TIMESTAMP NOT NULL,
    reason          VARCHAR(200)   -- 'initial', 'late invoice', 'warranty cost', 'price correction'
);

-- Grain: one row per human-review task closed or open. Powers the
-- Ops/Data-Quality dashboard in Phase 8.
CREATE TABLE fact_review_queue (
    task_key        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_key      BIGINT REFERENCES dim_data_source(source_key),
    assigned_staff_key BIGINT REFERENCES dim_staff(staff_key),
    created_date_key INT REFERENCES dim_date(date_key),
    resolved_date_key INT REFERENCES dim_date(date_key),
    confidence_score NUMERIC(4,3),
    resolution_hours NUMERIC(8,2),
    status          VARCHAR(20)
);
