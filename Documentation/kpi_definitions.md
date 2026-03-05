
# KPI Definitions

## Total Revenue
Total amount of payments received.

SQL Logic:
SUM(payments.amount)

---

## Outstanding Balance
Remaining amount to be paid by customers.

Formula:
booking_price - total_payments

---

## Booking Conversion Rate
Percentage of units booked out of available inventory.

Formula:
booked_units / total_units

---

## Inventory Status
Units categorized as:

- Available
- Reserved
- Booked
- Sold

---

## Monthly Payment Collection
Total payments collected per month.
