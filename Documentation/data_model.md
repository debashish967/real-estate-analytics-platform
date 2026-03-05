
# Data Model

## Core Entities

### Clients
Stores customer information.

### Projects
Represents real estate projects.

### Blocks
Sub-divisions within a project.

### Units
Individual apartments or plots.

### Bookings
Tracks when a client reserves a unit.

### Payments
Records payment transactions.

### Payment Schedules
Defines installment structure.

### Agreements
Generated when payment threshold is reached.

## Relationships

Client → Booking → Unit
Unit → Block → Project
Booking → Payments
Booking → Payment Schedule
Booking → Agreement
