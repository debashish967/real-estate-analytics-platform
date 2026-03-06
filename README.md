# 🏢 Real Estate Analytics Platform

End-to-End **Data Platform for Real Estate Operations and Analytics**
built using PostgreSQL, Supabase, Google Apps Script, and BI Dashboards.

This project demonstrates how to design a **production-style data
system** that manages real estate inventory, bookings, payments,
agreements, and business analytics.

------------------------------------------------------------------------

# 📊 Project Overview

Real estate companies often manage operations using spreadsheets which
leads to:

-   Data inconsistencies
-   Manual tracking of payments
-   Lack of operational visibility
-   No analytics for decision making

This platform solves those problems by creating a **centralized data
architecture with automated workflows and analytics dashboards**.

------------------------------------------------------------------------

# 🧩 System Architecture

    Google Sheets
          │
          ▼
    Google Apps Script
          │
          ▼
    Supabase RPC API
          │
          ▼
    PostgreSQL Database
          │
          ▼
    Analytics Views
          │
          ▼
    Power BI / Looker Studio Dashboard

------------------------------------------------------------------------

# 🔁 Data Flow

1.  Operations team enters booking and payment data into **Google
    Sheets**
2.  **Google Apps Script** sends requests to Supabase RPC functions
3.  **PostgreSQL database** processes logic using SQL functions and
    triggers
4.  Data is transformed into **analytics views**
5.  **BI dashboards** visualize KPIs and business insights

------------------------------------------------------------------------

# 🗄 Database Design

Core relational tables:

-   clients
-   projects
-   blocks
-   units
-   bookings
-   payments
-   payment_schedules
-   agreements

The database is designed with **normalized relational structure and
automated workflows**.

------------------------------------------------------------------------

# ⚙️ Automation Workflows

Implemented using **SQL functions, triggers and Apps Script
automation**.

Automated processes include:

-   Booking creation
-   Payment schedule generation
-   FIFO payment allocation
-   Agreement eligibility checks
-   Unit lifecycle status management

These workflows simulate a **real business transaction system**.

------------------------------------------------------------------------

# 📈 Analytics Layer

Analytics views were designed to power dashboards and reporting.

Example KPIs:

-   Total Revenue Collected
-   Outstanding Payment Balance
-   Booking Conversion Rate
-   Inventory Availability
-   Monthly Payment Collection
-   Unit Status Distribution

These metrics help management **monitor revenue and sales performance**.

------------------------------------------------------------------------

# 📊 Dashboard Capabilities

Dashboards built in Power BI / Looker Studio provide:

-   Revenue trend analysis
-   Inventory tracking
-   Booking performance
-   Payment collection monitoring

The analytics layer supports **real-time decision making for management
teams**.

------------------------------------------------------------------------

# 🛠 Technology Stack

  Layer           Technology
  --------------- --------------------------
  Data Entry      Google Sheets
  Automation      Google Apps Script
  Backend         Supabase
  Database        PostgreSQL
  Analytics       SQL Views
  Visualization   Power BI / Looker Studio

------------------------------------------------------------------------

# 🧠 Skills Demonstrated

This project demonstrates real-world **data engineering and analytics
engineering skills**:

-   Data Architecture Design
-   Relational Database Modeling
-   SQL Functions & Triggers
-   Workflow Automation
-   Data Pipelines
-   Analytics Engineering
-   Business Intelligence Dashboards

------------------------------------------------------------------------

## Dashboard Preview

Below are sample dashboards built from the analytics views in the PostgreSQL database.

### Sales & Revenue Dashboard
![Sales Dashboard](dashboards/Screenshot.png)

### Payment Tracking Dashboard
![Payment Dashboard](dashboards/Screenshots.png)

------------------------------------------------------------------------
# 📂 Repository Structure

    real-estate-analytics-platform

    database/
    tables.sql
    functions_triggers.sql
    views.sql

    automation/
    apps_script.js

    analytics/
    analytics_views.sql

    architecture/
    system_architecture.png
    data_flow_diagram.png

    dashboards/
    dashboard_screenshot.png

    documentation/
    business_problem.md
    system_design.md
    data_model.md
    kpi_definitions.md

------------------------------------------------------------------------

# 🚀 Business Value

This system enables real estate businesses to:

-   Track unit inventory accurately
-   Manage bookings efficiently
-   Monitor customer payments
-   Automate agreement workflows
-   Analyze financial performance

It replaces fragmented spreadsheets with a **scalable analytics-ready
data platform**.

------------------------------------------------------------------------

# 👨‍💻 Author

Data Analyst / Analytics Engineer specializing in:

-   SQL & PostgreSQL
-   Data Modeling
-   Analytics Engineering
-   Dashboard Development
-   Business Data Systems
-   System Aytomation
-   System Architect

------------------------------------------------------------------------

System Founder
System designed and maintained by:
 (Debashish Borah)
 Data & Automation Specialist


⭐ If you found this project useful, consider giving the repository a
star!
