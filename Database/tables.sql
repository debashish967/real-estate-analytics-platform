-- ================================
-- CLEAN PAYMENT SYSTEM STRUCTURE
-- ================================
-- Drop triggers first
drop trigger IF exists trg_payment_after_insert on payments;

-- Drop functions
drop function IF exists fn_handle_payment_insert ();

drop function IF exists sp_insert_payment;

drop function IF exists sp_create_schedule;

drop function IF exists sp_get_due_reminders ();

drop function IF exists sp_mark_reminder_sent;

-- Drop views
drop view IF exists v_schedule_financials;

drop view IF exists v_booking_financials;

drop view IF exists v_pending_payments;

drop view IF exists v_overdue_payments;

-- Drop tables (dependency order)
drop table if exists payments CASCADE;

drop table if exists payment_schedules CASCADE;

-- Drop in dependency order
drop table if exists payments CASCADE;

drop table if exists payment_schedules CASCADE;

drop table if exists bookings CASCADE;

create table projects (
  project_id SERIAL primary key,
  project_name VARCHAR(150) not null,
  total_blocks INT,
  location VARCHAR(200),
  status VARCHAR(30) default 'Active',
  start_date DATE,
  created_at TIMESTAMPTZ default NOW(),
  constraint chk_project_status check (status in ('Active', 'Completed', 'On Hold'))
);

create table blocks (
  block_id SERIAL primary key,
  project_id INT not null,
  block_code VARCHAR(10) not null,
  total_floors INT,
  created_at TIMESTAMPTZ default NOW(),
  constraint fk_blocks_project foreign KEY (project_id) references projects (project_id) on delete CASCADE,
  constraint uq_block_per_project unique (project_id, block_code)
);

create table units (
  unit_id SERIAL primary key,
  project_id INT not null,
  block_id INT not null,
  unit_number VARCHAR(20) not null,
  floor_number INT,
  unit_type VARCHAR(20),
  carpet_area_in_sqft NUMERIC(10, 2),
  builtup_area_in_sqft NUMERIC(10, 2),
  super_builtup_area_in_sqft NUMERIC(10, 2),
  parking_code VARCHAR(20),
  parking_type VARCHAR(30),
  parking_area_in_sqft NUMERIC(10, 2),
  electricity_load NUMERIC(6, 2),
  terrace_area_in_sqft NUMERIC(10, 2),
  balcony_area_in_sqft NUMERIC(10, 2),
  rate_per_sqft NUMERIC(10, 2),
  total_price NUMERIC(12, 2),
  status VARCHAR(20) default 'Available',
  created_at TIMESTAMPTZ default NOW(),
  constraint fk_units_project foreign KEY (project_id) references projects (project_id) on delete CASCADE,
  constraint fk_units_block foreign KEY (block_id) references blocks (block_id) on delete CASCADE,
  constraint uq_unit_per_project unique (project_id, unit_number),
  constraint chk_unit_status check (status in ('Available', 'Booked', 'Sold'))
);

create table clients (
  client_id SERIAL primary key,
  client_code VARCHAR(30) unique not null,
  client_name VARCHAR(150) not null,
  phone VARCHAR(20),
  dob DATE,
  email VARCHAR(150),
  profession VARCHAR(100),
  address TEXT,
  id_type VARCHAR(50),
  id_number VARCHAR(50),
  created_at TIMESTAMPTZ default NOW()
);

-- Recreate table with new column
create table bookings (
  booking_id SERIAL primary key,
  booking_code VARCHAR(50) unique not null,
  project_id INT not null,
  unit_id INT not null,
  client_id INT not null,
  booking_date DATE default CURRENT_DATE,
  booking_price NUMERIC(12, 2) not null,
  agreement_threshold_percent NUMERIC(5, 2) default 20,
  total_paid NUMERIC(12, 2) default 0,
  booking_status VARCHAR(20) default 'Booked',
  booked_by TEXT,
  remarks TEXT,
  constraint fk_booking_project foreign KEY (project_id) references projects (project_id) on delete CASCADE,
  constraint fk_booking_unit foreign KEY (unit_id) references units (unit_id),
  constraint fk_booking_client foreign KEY (client_id) references clients (client_id),
  constraint chk_booking_status check (
    booking_status in ('Booked', 'Completed', 'Cancelled')
  ),
  created_at TIMESTAMPTZ default NOW()
);

alter table public.bookings
add column schedule_template VARCHAR(100);

create index idx_bookings_template on public.bookings (schedule_template);

alter table public.bookings
add constraint fk_booking_schedule_template foreign KEY (schedule_template) references public.schedule_templates_master (template_name);

create table agreements (
  agreement_id SERIAL primary key,
  booking_id INT not null unique,
  client_id INT not null,
  pan_number VARCHAR(20),
  agreement_date DATE,
  agreement_status VARCHAR(20) default 'Pending',
  created_at TIMESTAMPTZ default NOW(),
  constraint fk_agreement_booking foreign KEY (booking_id) references bookings (booking_id) on delete CASCADE,
  constraint fk_agreement_client foreign KEY (client_id) references clients (client_id),
  constraint chk_agreement_status check (agreement_status in ('Pending', 'Completed'))
);

alter table agreements
add column unit_number VARCHAR(50);

update agreements a
set
  unit_number = u.unit_number
from
  bookings b
  join units u on b.unit_id = u.unit_id
where
  a.booking_id = b.booking_id;

alter table agreements
alter column unit_number
set not null;

create table payment_schedules (
  schedule_id SERIAL primary key,
  booking_id INT not null,
  instalment_no INT not null check (instalment_no between 1 and 15),
  milestone_name VARCHAR(100),
  due_date DATE not null,
  due_amount NUMERIC(12, 2) not null,
  gst_amount NUMERIC(12, 2) default 0,
  status VARCHAR(20) default 'Pending' check (
    status in ('Pending', 'Partially Paid', 'Paid', 'Overdue')
  ),
  last_reminder_sent_at TIMESTAMPTZ,
  remarks TEXT,
  constraint fk_schedule_booking foreign KEY (booking_id) references bookings (booking_id) on delete CASCADE,
  constraint uq_booking_instalment unique (booking_id, instalment_no),
  created_at TIMESTAMPTZ default (NOW() AT TIME ZONE 'Asia/Kolkata')
);

create table public.payments (
  payment_id SERIAL primary key,
  project_id INTEGER not null,
  booking_id INTEGER not null,
  schedule_id INTEGER null,
  receipt_no VARCHAR(50) not null unique,
  payment_date DATE not null,
  amount NUMERIC(12, 2) not null, -- Total Amount (Basic + GST)
  basic_amount NUMERIC(12, 2) not null,
  gst_amount NUMERIC(12, 2) not null default 0,
  payment_mode VARCHAR(50),
  payment_type VARCHAR(30),
  bank_name VARCHAR(100),
  remarks TEXT,
  created_at TIMESTAMPTZ default (now() AT TIME ZONE 'Asia/Kolkata'),
  -- Foreign Keys
  constraint fk_payment_project foreign KEY (project_id) references projects (project_id) on delete CASCADE,
  constraint fk_payment_booking foreign KEY (booking_id) references bookings (booking_id),
  -- STRICT composite FK (very important)
  constraint fk_payment_schedule_strict foreign KEY (schedule_id, booking_id) references payment_schedules (schedule_id, booking_id) on delete CASCADE,
  -- Payment type validation
  constraint payments_payment_type_check check (payment_type in ('Self Transfer', 'Loan')),
  -- Ensure accounting integrity
  constraint chk_amount_match check (amount = basic_amount + gst_amount)
);

-- STEP 1 — Drop old payment trigger
drop trigger IF exists trg_payment_after_insert on payments;

alter table payments
drop constraint fk_payment_schedule;

alter table payment_schedules
add constraint uq_schedule_booking_pair unique (schedule_id, booking_id);

alter table payments
add constraint fk_payment_schedule_strict foreign KEY (schedule_id, booking_id) references payment_schedules (schedule_id, booking_id) on delete CASCADE;

alter table payments
alter column schedule_id
drop not null;

alter table public.payment_schedules
alter column due_date
drop not null;

--Add an advance column to bookings
alter table bookings
add column advance_amount NUMERIC default 0 check (advance_amount >= 0);

-- Drop triggers first (optional but clean)
drop trigger IF exists trg_allocate_payment_fifo on payments;

drop trigger IF exists trg_payment_recalculate on payments;

-- Drop tables
drop table if exists payments CASCADE;

drop table if exists staging_payments CASCADE;

create table public.staging_payments (
  project_name VARCHAR(100),
  booking_code VARCHAR(50),
  instalment_no INTEGER,
  receipt_no VARCHAR(50),
  payment_date DATE,
  amount NUMERIC(12, 2),
  basic_amount NUMERIC(12, 2),
  gst_amount NUMERIC(12, 2),
  payment_mode VARCHAR(50),
  payment_type VARCHAR(50),
  bank_name VARCHAR(100),
  created_at TIMESTAMPTZ default now()
);

-- Check rows with missing due_date
select
  *
from
  staging_payment_schedules
where
  due_date is null;

insert into
  payment_schedules (
    booking_id,
    instalment_no,
    milestone_name,
    due_date,
    due_amount,
    gst_amount,
    status,
    last_reminder_sent_at,
    remarks,
    created_at
  )
select
  b.booking_id,
  s.instalment_no,
  s.milestone_name,
  s.due_date,
  s.due_amount,
  COALESCE(s.gst_amount, 0),
  COALESCE(s.status, 'Pending'),
  s.last_reminder_sent_at,
  s.remarks,
  COALESCE(s.created_at, NOW())
from
  staging_payment_schedules s
  join bookings b on trim(upper(s.booking_code)) = trim(upper(b.booking_code));

-- Create Allocation Table
create table payment_allocations (
  allocation_id SERIAL primary key,
  payment_id INT references payments (payment_id) on delete CASCADE,
  booking_id INT references bookings (booking_id) on delete CASCADE,
  schedule_id INT references payment_schedules (schedule_id),
  allocated_amount NUMERIC not null,
  created_at TIMESTAMP default NOW()
);

create table public.schedule_templates_details (
  id SERIAL primary key,
  template_name VARCHAR(100) not null,
  instalment_no INTEGER not null,
  milestone_name TEXT not null,
  percentage NUMERIC(5, 2) not null,
  constraint fk_template_details foreign KEY (template_name) references public.schedule_templates_master (template_name) on delete CASCADE
);

-- create table schedule_templates
create table public.schedule_templates (
  template_name varchar(100) not null,
  instalment_no integer not null,
  milestone_name varchar(150) not null,
  percentage numeric(5, 2) not null,
  constraint schedule_templates_pk primary key (template_name, instalment_no)
);