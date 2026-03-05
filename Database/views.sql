CREATE SCHEMA IF NOT EXISTS analytics;
-- Unit Financial Summary
CREATE OR REPLACE VIEW analytics.v_unit_financials AS
SELECT
    b.booking_id,
    b.booking_code,
    p.project_name,
    u.unit_number,
    c.client_name,
    u.parking_code,
    b.booking_price AS total_demand,
    b.total_paid AS total_received,
    (b.booking_price - b.total_paid) AS total_balance,
    
    CASE
        WHEN b.booking_price > 0
        THEN ROUND((b.total_paid / b.booking_price) * 100,2)
        ELSE 0
    END AS received_percent,
    
    a.agreement_status,
    u.status AS unit_status

FROM bookings b
JOIN units u ON u.unit_id = b.unit_id
JOIN projects p ON p.project_id = b.project_id
JOIN clients c ON c.client_id = b.client_id
LEFT JOIN agreements a ON a.booking_id = b.booking_id;
-- Current Pending Schedule
CREATE OR REPLACE VIEW analytics.v_current_due_schedule AS
SELECT
    ps.booking_id,
    ps.instalment_no,
    ps.milestone_name,
    ps.due_date,
    ps.due_amount,
    ps.status,
    ps.last_reminder_sent_at
FROM payment_schedules ps
WHERE ps.status IN ('Pending','Partially Paid');
-- Unit Dashboard Dataset (Main View)
CREATE OR REPLACE VIEW analytics.v_unit_dashboard AS
SELECT
    f.project_name,
    f.unit_number,
    f.client_name,
    f.parking_code,
    f.unit_status,
    f.agreement_status,

    f.total_demand,
    f.total_received,
    f.total_balance,
    f.received_percent,

    s.instalment_no,
    s.milestone_name,
    s.due_date,
    s.due_amount,
    s.status AS schedule_status,
    s.last_reminder_sent_at

FROM analytics.v_unit_financials f
LEFT JOIN analytics.v_current_due_schedule s
ON f.booking_id = s.booking_id;












-- MASTER ANALYTICS BASE QUERY (Use this everywhere)
SELECT
    p.project_name,
    u.unit_number,
    b.booking_code,
    b.booking_price AS total_demand,
    COALESCE(SUM(pay.amount),0) AS total_received,
    (b.booking_price - COALESCE(SUM(pay.amount),0)) AS total_balance,
    CASE 
        WHEN b.booking_price > 0 
        THEN ROUND((COALESCE(SUM(pay.amount),0) / b.booking_price) * 100,2)
        ELSE 0
    END AS received_percent

FROM bookings b

JOIN projects p 
ON b.project_id = p.project_id

JOIN units u 
ON b.unit_id = u.unit_id

LEFT JOIN payments pay 
ON b.booking_id = pay.booking_id

GROUP BY
    p.project_name,
    u.unit_number,
    b.booking_code,
    b.booking_price
;

-- KPI QUERY (Total Demand / Received / Balance)
SELECT
    SUM(b.booking_price) AS total_demand,
    COALESCE(SUM(pay.amount),0) AS total_received,
    SUM(b.booking_price) - COALESCE(SUM(pay.amount),0) AS total_balance,
    
    CASE 
        WHEN SUM(b.booking_price) > 0
        THEN ROUND((COALESCE(SUM(pay.amount),0) / SUM(b.booking_price)) * 100,2)
        ELSE 0
    END AS received_percent

FROM bookings b

LEFT JOIN payments pay
ON b.booking_id = pay.booking_id;

-- PIE CHART QUERY(Unit vs Total Received)
SELECT
    u.unit_number,
    COALESCE(SUM(p.amount),0) AS total_received

FROM bookings b

JOIN units u
ON b.unit_id = u.unit_id

LEFT JOIN payments p
ON b.booking_id = p.booking_id

GROUP BY u.unit_number
ORDER BY total_received DESC;

-- BAR CHART QUERY (Important Analytics)
SELECT
    u.unit_number,
    b.booking_price AS total_demand,
    COALESCE(SUM(p.amount),0) AS total_received,
    b.booking_price - COALESCE(SUM(p.amount),0) AS total_balance

FROM bookings b

JOIN units u
ON b.unit_id = u.unit_id

LEFT JOIN payments p
ON b.booking_id = p.booking_id

GROUP BY
    u.unit_number,
    b.booking_price

ORDER BY u.unit_number;

-- Financial Dashboard
CREATE OR REPLACE VIEW vw_unit_financial_summary AS

SELECT
    p.project_name,
    u.unit_number,
    b.booking_code,
    b.booking_price AS total_demand,
    COALESCE(SUM(pay.amount),0) AS total_received,
    (b.booking_price - COALESCE(SUM(pay.amount),0)) AS total_balance,
    CASE 
        WHEN b.booking_price > 0 
        THEN ROUND((COALESCE(SUM(pay.amount),0) / b.booking_price) * 100,2)
        ELSE 0
    END AS received_percent

FROM bookings b
JOIN projects p ON b.project_id = p.project_id
JOIN units u ON b.unit_id = u.unit_id
LEFT JOIN payments pay ON b.booking_id = pay.booking_id

GROUP BY
    p.project_name,
    u.unit_number,
    b.booking_code,
    b.booking_price;


Drop view vw_dashboard_master;
CREATE OR REPLACE VIEW vw_dashboard_master AS
SELECT 
    b.booking_id,
    b.booking_code,
    p.project_id,
    p.project_name,
    u.unit_id,
    u.unit_number,

    -- RAW numeric fields (for calculations)
    b.booking_price AS booking_price_raw,
    b.total_paid AS total_paid_raw,
    (b.booking_price - b.total_paid) AS balance_amount_raw,

    -- Display formatted fields (Indian format)
    TO_CHAR(b.booking_price, 'FM99,99,99,99,999') AS booking_price_display,
    TO_CHAR(b.total_paid, 'FM99,99,99,99,999') AS total_received_display,
    TO_CHAR((b.booking_price - b.total_paid), 'FM99,99,99,99,999') AS balance_amount_display,

    ROUND(
        (b.total_paid / NULLIF(b.booking_price,0)) * 100,
        2
    ) AS received_percent,

    b.booking_status,
    COALESCE(a.agreement_status, 'Pending') AS agreement_status

FROM bookings b
LEFT JOIN projects p 
    ON b.project_id = p.project_id
LEFT JOIN units u 
    ON b.unit_id = u.unit_id
LEFT JOIN agreements a 
    ON b.booking_id = a.booking_id;


CREATE VIEW vw_agreement_dashboard AS
SELECT 
    b.booking_id,
    b.booking_code,
    p.project_name,
    u.unit_number,
    b.booking_price,
    b.total_paid,
    (b.booking_price - b.total_paid) AS balance_amount,
    ROUND(
        (b.total_paid / NULLIF(b.booking_price,0)) * 100,
        2
    ) AS received_percent,
    a.agreement_id,
    CASE 
        WHEN a.agreement_id IS NULL THEN 'Not Created'
        ELSE a.agreement_status
    END AS agreement_status
FROM bookings b
LEFT JOIN projects p ON b.project_id = p.project_id
LEFT JOIN units u ON b.unit_id = u.unit_id
LEFT JOIN agreements a ON b.booking_id = a.booking_id;

-- Create Agreement Summary View (Optional but Recommended)
CREATE OR REPLACE VIEW vw_agreement_summary AS
SELECT
    agreement_status,
    COUNT(*) AS total_count
FROM agreements
GROUP BY agreement_status;


ALTER TABLE payment_schedules
DROP COLUMN gst_amount;
ALTER TABLE payments
DROP COLUMN instalment_no;
SELECT proname
FROM pg_proc
WHERE prosrc ILIKE '%payments.instalment_no%';
SELECT tgname
FROM pg_trigger
WHERE pg_get_triggerdef(oid) ILIKE '%instalment_no%';

-- Unit live status view
CREATE OR REPLACE VIEW public.vw_unit_live_status AS

WITH latest_active_booking AS (
    SELECT DISTINCT ON (b.unit_id)
        b.booking_id,
        b.unit_id,
        b.client_id,
        b.booking_status,
        b.booking_price,
        b.total_paid,
        b.created_at
    FROM bookings b
    WHERE b.booking_status NOT IN ('Cancelled')
    ORDER BY b.unit_id, b.created_at DESC
)

SELECT
    p.project_name,
    bl.block_code,
    u.floor_number,
    u.unit_id,
    u.unit_number,
    u.status AS unit_status,
    u.parking_code,

    lab.booking_id,
    lab.booking_status,
    lab.booking_price,
    lab.total_paid,

    ROUND(
        CASE 
            WHEN lab.booking_price IS NOT NULL AND lab.booking_price > 0
            THEN (lab.total_paid / lab.booking_price) * 100
            ELSE 0
        END
    , 2) AS payment_percent,

    c.client_name,

    a.agreement_status,
    a.agreement_date

FROM units u
JOIN projects p ON u.project_id = p.project_id
JOIN blocks bl ON u.block_id = bl.block_id

LEFT JOIN latest_active_booking lab 
    ON u.unit_id = lab.unit_id

LEFT JOIN clients c 
    ON lab.client_id = c.client_id

LEFT JOIN agreements a 
    ON lab.booking_id = a.booking_id;