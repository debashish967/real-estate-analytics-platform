
# System Design

## Architecture Overview

Google Sheets → Apps Script → Supabase RPC → PostgreSQL → Analytics Views → BI Dashboards

## Components

### Data Entry Layer
Google Sheets used by operations team to enter:

- client information
- unit bookings
- payments

### Automation Layer
Google Apps Script performs:

- API calls to Supabase
- booking creation
- payment processing
- trigger-based workflows

### Database Layer
PostgreSQL (Supabase) stores:

- clients
- projects
- blocks
- units
- bookings
- payments
- agreements

SQL functions and triggers automate business logic.

### Analytics Layer
Analytics views generate KPIs such as:

- revenue collected
- outstanding balances
- unit availability
- booking trends

### Dashboard Layer
Power BI / Looker Studio visualizes analytics views.
