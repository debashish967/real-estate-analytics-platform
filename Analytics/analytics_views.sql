
-- Revenue View
CREATE VIEW revenue_summary AS
SELECT
    DATE_TRUNC('month', payment_date) AS month,
    SUM(amount) AS total_revenue
FROM payments
GROUP BY 1
ORDER BY 1;

-- Outstanding Balance View
CREATE VIEW outstanding_balances AS
SELECT
    b.booking_id,
    b.unit_id,
    b.total_price,
    COALESCE(SUM(p.amount),0) AS paid_amount,
    b.total_price - COALESCE(SUM(p.amount),0) AS balance
FROM bookings b
LEFT JOIN payments p ON b.booking_id = p.booking_id
GROUP BY b.booking_id;

-- Inventory Status View
CREATE VIEW inventory_status AS
SELECT
    status,
    COUNT(*) AS unit_count
FROM units
GROUP BY status;
