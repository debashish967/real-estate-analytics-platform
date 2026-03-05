--Professional Clean Reset Script (Recommended)
CREATE OR REPLACE FUNCTION sp_reset_test_data()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE 
        payments,
        payment_schedules,
        agreements,
        bookings
    RESTART IDENTITY CASCADE;

    UPDATE units
    SET status = 'Available';
END;
$$;

-- Add 'Hold' to units status
ALTER TABLE units DROP CONSTRAINT chk_unit_status;

ALTER TABLE units ADD CONSTRAINT chk_unit_status CHECK (
  status IN (
    'Available',
    'Hold',
    'Reserved',
    'Ready for Agreement',
    'Payment Collection',
    'Sold'
  )
);

-- Booking Insert Logic
CREATE OR REPLACE FUNCTION fn_handle_booking_insert()
RETURNS TRIGGER AS $$
BEGIN
    -- Set booking status
    NEW.booking_status := 'Holding';

    -- Update unit status
    UPDATE units
    SET status = 'Hold'
    WHERE unit_id = NEW.unit_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF Exist trg_booking_insert;
CREATE TRIGGER trg_booking_insert
BEFORE INSERT ON bookings
FOR EACH ROW
EXECUTE FUNCTION fn_handle_booking_insert();

-- Booking Cancellation Trigger
CREATE OR REPLACE FUNCTION fn_handle_booking_update()
RETURNS TRIGGER AS $$
BEGIN
    -- If booking is cancelled
    IF NEW.booking_status = 'Cancelled'
       AND OLD.booking_status IS DISTINCT FROM 'Cancelled'
    THEN
        -- Set unit back to Available
        UPDATE units
        SET status = 'Available'
        WHERE unit_id = NEW.unit_id;

        -- Cancel agreement if exists
        UPDATE agreements
        SET agreement_status = 'Cancelled'
        WHERE booking_id = NEW.booking_id;

        -- Cancel all schedules
        UPDATE payment_schedules
        SET status = 'Cancelled'
        WHERE booking_id = NEW.booking_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_booking_update
AFTER UPDATE ON bookings
FOR EACH ROW
EXECUTE FUNCTION fn_handle_booking_update();
EXECUTE FUNCTION fn_handle_agreement_update();
-- Agreement Trigger
CREATE OR REPLACE FUNCTION public.fn_handle_agreement_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_unit_id INT;
BEGIN
    -- Only run on UPDATE
    IF TG_OP <> 'UPDATE' THEN
        RETURN NEW;
    END IF;

    -- Only act if agreement_status actually changed
    IF NEW.agreement_status IS NOT DISTINCT FROM OLD.agreement_status THEN
        RETURN NEW;
    END IF;

    -- Get unit_id
    SELECT unit_id INTO v_unit_id
    FROM bookings
    WHERE booking_id = NEW.booking_id;

    -- If agreement marked Done
    IF NEW.agreement_status = 'Done' THEN
        UPDATE bookings
        SET booking_status = 'Payment Collection'
        WHERE booking_id = NEW.booking_id;

        UPDATE units
        SET status = 'Payment Collection'
        WHERE unit_id = v_unit_id;
    END IF;

    -- If agreement marked Cancelled
    IF NEW.agreement_status = 'Cancelled' THEN
        UPDATE bookings
        SET booking_status = 'Cancelled'
        WHERE booking_id = NEW.booking_id;

        UPDATE units
        SET status = 'Available'
        WHERE unit_id = v_unit_id;

        UPDATE payment_schedules
        SET status = 'Cancelled'
        WHERE booking_id = NEW.booking_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER trg_agreement_update ON agreements;

CREATE TRIGGER trg_agreement_update
AFTER UPDATE ON agreements
FOR EACH ROW
EXECUTE FUNCTION public.fn_handle_agreement_update();


DROP TRIGGER IF EXISTS trg_allocate_payment_fifo ON payments;
DROP FUNCTION IF EXISTS fn_allocate_payment_fifo();

DROP TRIGGER IF EXISTS trg_check_agreement_on_payment ON payments;
DROP FUNCTION IF EXISTS fn_trigger_check_agreement();

DROP FUNCTION IF EXISTS fn_allocate_payment_fifo() CASCADE;

-- Payment Insert Trigger Function FIFO
CREATE OR REPLACE FUNCTION fn_allocate_payment_fifo()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_remaining NUMERIC := NEW.amount;
    v_due NUMERIC;
    v_paid_on_sched NUMERIC;
    sched RECORD;
    v_booking_price NUMERIC;
    v_unit_id INT;
BEGIN
    -- Loop schedules FIFO
    FOR sched IN
        SELECT *
        FROM payment_schedules
        WHERE booking_id = NEW.booking_id
          AND status IN ('Pending','Partially Paid')
        ORDER BY instalment_no, due_date
    LOOP
        EXIT WHEN v_remaining <= 0;

        -- How much already allocated to this schedule
        SELECT COALESCE(SUM(pa.allocated_amount),0)
        INTO v_paid_on_sched
        FROM payment_allocations pa
        WHERE pa.schedule_id = sched.schedule_id;

        v_due := sched.due_amount - v_paid_on_sched;

        IF v_due <= 0 THEN
            CONTINUE;
        END IF;

        IF v_remaining >= v_due THEN
            INSERT INTO payment_allocations (
                payment_id,
                booking_id,
                schedule_id,
                allocated_amount
            )
            VALUES (
                NEW.payment_id,
                NEW.booking_id,
                sched.schedule_id,
                v_due
            );

            UPDATE payment_schedules
            SET status = 'Paid'
            WHERE schedule_id = sched.schedule_id;

            v_remaining := v_remaining - v_due;

        ELSE
            INSERT INTO payment_allocations (
                payment_id,
                booking_id,
                schedule_id,
                allocated_amount
            )
            VALUES (
                NEW.payment_id,
                NEW.booking_id,
                sched.schedule_id,
                v_remaining
            );

            UPDATE payment_schedules
            SET status = 'Partially Paid'
            WHERE schedule_id = sched.schedule_id;

            v_remaining := 0;
        END IF;
    END LOOP;

    -- Recalculate total_paid from real payments table only
    UPDATE bookings
    SET total_paid = COALESCE((
        SELECT SUM(amount)
        FROM payments
        WHERE booking_id = NEW.booking_id
    ),0)
    WHERE booking_id = NEW.booking_id;

    -- Get booking details
    SELECT unit_id, booking_price
    INTO v_unit_id, v_booking_price
    FROM bookings
    WHERE booking_id = NEW.booking_id;

    -- Agreement check
    PERFORM sp_check_agreement_creation(NEW.booking_id);

    -- If fully paid mark sold
    IF (SELECT total_paid FROM bookings WHERE booking_id = NEW.booking_id) >= v_booking_price THEN
        UPDATE units SET status = 'Sold' WHERE unit_id = v_unit_id;
        UPDATE bookings SET booking_status = 'Completed' WHERE booking_id = NEW.booking_id;
    END IF;

    RETURN NULL;
END;
$$;

-- Attach Trigger to Payments Table
DROP TRIGGER IF EXISTS trg_allocate_payment_fifo ON payments;

CREATE TRIGGER trg_allocate_payment_fifo
AFTER INSERT ON payments
FOR EACH ROW
WHEN (NEW.schedule_id IS NULL)  -- only trigger for unscheduled payments
EXECUTE FUNCTION fn_allocate_payment_fifo();

-- Create Helper Function for Agreement Auto-Creation
CREATE OR REPLACE FUNCTION sp_check_agreement_creation(p_booking_id INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_paid NUMERIC;
    v_threshold NUMERIC;
    v_unit_id INT;
    v_agreement_exists INT;
BEGIN
    -- Get booking info
    SELECT total_paid, agreement_threshold_amount, unit_id
    INTO v_total_paid, v_threshold, v_unit_id
    FROM bookings
    WHERE booking_id = p_booking_id;

    -- Check if agreement already exists
    SELECT COUNT(1)
    INTO v_agreement_exists
    FROM agreements
    WHERE booking_id = p_booking_id;

    -- Create agreement if threshold met and agreement does not exist
    IF v_total_paid >= v_threshold AND v_agreement_exists = 0 THEN

        INSERT INTO agreements (
            booking_id,
            client_id,
            agreement_status,
            created_at
        )
        SELECT booking_id, client_id, 'Pending', NOW()
        FROM bookings
        WHERE booking_id = p_booking_id;

        -- Update unit status
        UPDATE units
        SET status = 'Ready for Agreement'
        WHERE unit_id = v_unit_id;

        -- Update booking status
        UPDATE bookings
        SET booking_status = 'Agreement Pending'
        WHERE booking_id = p_booking_id;

    END IF;
END;
$$;

-- Agreement Status Update Trigger
-- Function to handle agreement completion
CREATE OR REPLACE FUNCTION fn_handle_agreement_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_unit_id INT;
BEGIN
    -- Get the unit_id from the booking
    SELECT unit_id INTO v_unit_id
    FROM bookings
    WHERE booking_id = NEW.booking_id;

    -- If agreement is marked 'Done', update statuses
    IF NEW.agreement_status = 'Done' THEN
        UPDATE bookings
        SET booking_status = 'Payment Collection'
        WHERE booking_id = NEW.booking_id;

        UPDATE units
        SET status = 'Payment Collection'
        WHERE unit_id = v_unit_id;
    END IF;

    -- If agreement is marked 'Cancelled', revert statuses
    IF NEW.agreement_status = 'Cancelled' THEN
        -- Booking status to Cancelled
        UPDATE bookings
        SET booking_status = 'Cancelled'
        WHERE booking_id = NEW.booking_id;

        -- Unit status to Available
        UPDATE units
        SET status = 'Available'
        WHERE unit_id = v_unit_id;

        -- Cancel all related payment schedules
        UPDATE payment_schedules
        SET status = 'Cancelled'
        WHERE booking_id = NEW.booking_id;
    END IF;

    RETURN NEW;
END;
$$;
-- Trigger Function to Call sp_check_agreement_creation
CREATE OR REPLACE FUNCTION fn_trigger_check_agreement()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Call the helper function for the booking of the inserted payment
    PERFORM sp_check_agreement_creation(NEW.booking_id);

    RETURN NEW;
END;
$$;

-- Drop the trigger if it already exists (safety)
DROP TRIGGER IF EXISTS trg_check_agreement_on_payment ON payments;

CREATE OR REPLACE FUNCTION fn_trigger_check_agreement()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Call the helper function to check if agreement should be created for this booking
    PERFORM sp_check_agreement_creation(NEW.booking_id);

    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_check_agreement_on_payment ON payments;

CREATE TRIGGER trg_check_agreement_on_payment
AFTER INSERT ON payments
FOR EACH ROW
EXECUTE FUNCTION fn_trigger_check_agreement();
-- Drop existing trigger if any
DROP TRIGGER IF EXISTS trg_agreement_update ON agreements;

-- Create trigger for agreement updates
CREATE TRIGGER trg_agreement_update
AFTER UPDATE ON agreements
FOR EACH ROW
EXECUTE FUNCTION fn_handle_agreement_update();

-- Cancellation Trigger
-- Function to handle booking or agreement cancellations
CREATE OR REPLACE FUNCTION fn_handle_cancellation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_unit_id INT;
BEGIN
    -- Ensure we are called by a trigger and NEW exists
    IF TG_OP IS NULL OR NEW IS NULL THEN
        RETURN NULL;
    END IF;

    -- Get the unit_id from the booking
    SELECT unit_id INTO v_unit_id
    FROM bookings
    WHERE booking_id = NEW.booking_id;

    -- Booking cancellation trigger logic
    IF TG_TABLE_NAME = 'bookings' AND TG_OP = 'UPDATE' THEN
        IF NEW.booking_status = 'Cancelled' THEN
            -- Update unit status
            UPDATE units
            SET status = 'Available'
            WHERE unit_id = v_unit_id;

            -- Cancel all agreements linked to booking
            UPDATE agreements
            SET agreement_status = 'Cancelled'
            WHERE booking_id = NEW.booking_id;

            -- Cancel all payment schedules linked to booking
            UPDATE payment_schedules
            SET status = 'Cancelled'
            WHERE booking_id = NEW.booking_id;
        END IF;
    END IF;

    -- Agreement cancellation trigger logic
    IF TG_TABLE_NAME = 'agreements' AND TG_OP = 'UPDATE' THEN
        IF NEW.agreement_status = 'Cancelled' THEN
            -- Update unit status
            UPDATE units
            SET status = 'Available'
            WHERE unit_id = v_unit_id;

            -- Update booking status
            UPDATE bookings
            SET booking_status = 'Cancelled'
            WHERE booking_id = NEW.booking_id;

            -- Cancel all payment schedules linked to booking
            UPDATE payment_schedules
            SET status = 'Cancelled'
            WHERE booking_id = NEW.booking_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- Trigger for bookings
DROP TRIGGER IF EXISTS trg_booking_cancel ON bookings;

CREATE TRIGGER trg_booking_cancel
AFTER UPDATE ON bookings
FOR EACH ROW
WHEN (OLD.booking_status IS DISTINCT FROM NEW.booking_status)
EXECUTE FUNCTION fn_handle_cancellation();

-- Trigger for agreements
DROP TRIGGER IF EXISTS trg_agreement_cancel ON agreements;

CREATE TRIGGER trg_agreement_cancel
AFTER UPDATE ON agreements
FOR EACH ROW
WHEN (OLD.agreement_status IS DISTINCT FROM NEW.agreement_status)
EXECUTE FUNCTION fn_handle_cancellation();

-- Create the sp_update_overdue() function
CREATE OR REPLACE FUNCTION sp_update_overdue()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE payment_schedules
    SET status = 'Overdue'
    WHERE status IN ('Pending','Partially Paid')
      AND due_date < CURRENT_DATE;
END;
$$;

-- Create a new RPC to insert bookings (recommended) Help for Apps Script 
CREATE OR REPLACE FUNCTION sp_create_booking(
    p_booking_code TEXT,
    p_project_name TEXT,
    p_unit_number TEXT,
    p_client_code TEXT,
    p_booking_date DATE,
    p_booking_price NUMERIC,
    p_threshold NUMERIC,
    p_schedule_template TEXT,
    p_booked_by TEXT,
    p_remarks TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_project_id INT;
    v_unit_id INT;
    v_client_id INT;
BEGIN
    -- Get IDs
    SELECT project_id INTO v_project_id FROM projects WHERE project_name = p_project_name;
    IF v_project_id IS NULL THEN
        RAISE EXCEPTION 'Project % not found', p_project_name;
    END IF;

    SELECT unit_id INTO v_unit_id FROM units WHERE unit_number = p_unit_number AND project_id = v_project_id;
    IF v_unit_id IS NULL THEN
        RAISE EXCEPTION 'Unit % not found for project %', p_unit_number, p_project_name;
    END IF;

    SELECT client_id INTO v_client_id FROM clients WHERE client_code = p_client_code;
    IF v_client_id IS NULL THEN
        RAISE EXCEPTION 'Client % not found', p_client_code;
    END IF;

    -- Insert booking
    INSERT INTO bookings (
        booking_code, project_id, unit_id, client_id,
        booking_date, booking_price, agreement_threshold_amount,
        schedule_template, booked_by, remarks
    )
    VALUES (
        p_booking_code, v_project_id, v_unit_id, v_client_id,
        p_booking_date, p_booking_price, p_threshold,
        p_schedule_template, p_booked_by, p_remarks
    );
END;
$$;

-- For the help of apps scripts insert_payment with sp_insert_payment
CREATE OR REPLACE FUNCTION public.sp_insert_payment_rpc(
    p_booking_code TEXT,
    p_instalment_no INT,
    p_receipt_no TEXT,
    p_payment_date DATE,
    p_amount NUMERIC,
    p_basic_amount NUMERIC,
    p_gst NUMERIC,
    p_mode TEXT,
    p_payment_type TEXT,
    p_bank TEXT,
    p_remarks TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_booking_id INT;
    v_project_id INT;
BEGIN
    -- Get booking_id and project_id
    SELECT booking_id, project_id
    INTO v_booking_id, v_project_id
    FROM bookings
    WHERE booking_code = p_booking_code;

    IF v_booking_id IS NULL THEN
        RAISE EXCEPTION 'Booking not found for code %', p_booking_code;
    END IF;

    -- Insert payment
    INSERT INTO payments (
        project_id,
        booking_id,
        receipt_no,
        payment_date,
        amount,
        basic_amount,
        gst_amount,
        payment_mode,
        payment_type,
        bank_name,
        remarks,
        created_at
    )
    VALUES (
        v_project_id,
        v_booking_id,
        p_receipt_no,
        p_payment_date,
        p_amount,
        p_basic_amount,
        p_gst,
        p_mode,
        p_payment_type,
        p_bank,
        p_remarks,
        NOW()
    );
END;
$$;

SELECT
    tgname AS trigger_name,
    pg_get_triggerdef(oid) AS trigger_definition
FROM pg_trigger
WHERE tgrelid = 'payments'::regclass;
CREATE OR REPLACE FUNCTION sp_insert_payment_debug(payload jsonb)
RETURNS payments
LANGUAGE plpgsql
AS $$
DECLARE
    v_payment payments;
BEGIN
    RAISE NOTICE 'RPC CALLED';

    INSERT INTO payments (
        project_id,
        booking_id,
        receipt_no,
        payment_date,
        amount,
        basic_amount,
        gst_amount,
        payment_mode,
        payment_type,
        bank_name,
        remarks
    )
    VALUES (
        (payload->>'project_id')::uuid,
        (payload->>'booking_id')::uuid,
        payload->>'receipt_no',
        (payload->>'payment_date')::date,
        (payload->>'amount')::numeric,
        (payload->>'basic_amount')::numeric,
        (payload->>'gst_amount')::numeric,
        payload->>'payment_mode',
        payload->>'payment_type',
        payload->>'bank_name',
        payload->>'remarks'
    )
    RETURNING * INTO v_payment;

    RETURN v_payment;
END;
$$;

-- sp_get_due_reminders
CREATE OR REPLACE FUNCTION sp_get_due_reminders()
RETURNS TABLE (
    schedule_id INT,
    instalment_no INT,
    due_date DATE,
    demand_amount NUMERIC,
    booking_code TEXT,
    client_name TEXT,
    email TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ps.schedule_id,
        ps.instalment_no,
        ps.due_date,
        ps.due_amount AS demand_amount,
        b.booking_code,
        c.client_name,
        c.email
    FROM payment_schedules ps
    JOIN bookings b ON ps.booking_id = b.booking_id
    JOIN agreements a ON a.booking_id = b.booking_id
    JOIN clients c ON b.client_id = c.client_id
    WHERE 
        a.status = 'Done'
        AND b.booking_status != 'Cancelled'
        AND ps.status IN ('Pending','Partially Paid')
        AND ps.last_reminder_sent_at IS NULL
        AND ps.due_date BETWEEN CURRENT_DATE 
                           AND CURRENT_DATE + INTERVAL '5 days';
END;
$$;

-- sp_mark_reminder_sent
CREATE OR REPLACE FUNCTION sp_mark_reminder_sent(
    p_schedule_id INT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE payment_schedules
    SET last_reminder_sent_at = NOW()
    WHERE schedule_id = p_schedule_id;
END;
$$;
-- Create Function fn_generate_payment_schedule
CREATE OR REPLACE FUNCTION public.fn_generate_payment_schedule()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    record RECORD;
    v_total_percentage numeric := 0;
    v_running_total numeric := 0;
    v_due_amount numeric;
    v_last_instalment integer;
BEGIN

    -- Validate template exists
    IF NOT EXISTS (
        SELECT 1 
        FROM schedule_templates 
        WHERE template_name = NEW.schedule_template
    ) THEN
        RAISE EXCEPTION 'Schedule template % does not exist', NEW.schedule_template;
    END IF;

    -- Validate total percentage = 100
    SELECT SUM(percentage)
    INTO v_total_percentage
    FROM schedule_templates
    WHERE template_name = NEW.schedule_template;

    IF v_total_percentage <> 100 THEN
        RAISE EXCEPTION 'Total percentage for template % is not 100', NEW.schedule_template;
    END IF;

    -- Get last instalment number
    SELECT MAX(instalment_no)
    INTO v_last_instalment
    FROM schedule_templates
    WHERE template_name = NEW.schedule_template;

    -- Generate schedules
    FOR record IN
        SELECT *
        FROM schedule_templates
        WHERE template_name = NEW.schedule_template
        ORDER BY instalment_no
    LOOP

        IF record.instalment_no < v_last_instalment THEN
            v_due_amount := ROUND((NEW.booking_price * record.percentage / 100), 2);
            v_running_total := v_running_total + v_due_amount;
        ELSE
            -- Last instalment rounding adjustment
            v_due_amount := NEW.booking_price - v_running_total;
        END IF;

        INSERT INTO payment_schedules (
            booking_id,
            instalment_no,
            milestone_name,
            due_date,
            due_amount,
            status
        )
        VALUES (
            NEW.booking_id,
            record.instalment_no,
            record.milestone_name,
            NULL,
            v_due_amount,
            'Pending'
        );

    END LOOP;

    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_generate_payment_schedule
AFTER INSERT ON public.bookings
FOR EACH ROW
WHEN (NEW.schedule_template IS NOT NULL)
EXECUTE FUNCTION public.fn_generate_payment_schedule();

CREATE OR REPLACE FUNCTION sp_insert_schedule_template(
  p_template_name TEXT,
  p_instalment_no INT,
  p_milestone_name TEXT,
  p_percentage NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO schedule_templates (template_name, instalment_no, milestone_name, percentage)
  VALUES (p_template_name, p_instalment_no, p_milestone_name, p_percentage);
END;
$$;
ALTER TABLE bookings
ADD COLUMN booking_id serial PRIMARY KEY;

ALTER TABLE bookings
ADD COLUMN project_id int REFERENCES projects(project_id);
