/* ============================= */
/* SUPABASE CONFIG               */
/* ============================= */

const scriptProperties = PropertiesService.getScriptProperties();

const SUPABASE_URL = scriptProperties.getProperty("SUPABASE_URL");
const SERVICE_ROLE_KEY = scriptProperties.getProperty("SERVICE_ROLE_KEY");

if (!SUPABASE_URL || SUPABASE_URL.trim() === "") {
  throw new Error("SUPABASE_URL not set in Script Properties");
}

if (!SERVICE_ROLE_KEY || SERVICE_ROLE_KEY.trim() === "") {
  throw new Error("SERVICE_ROLE_KEY not set in Script Properties");
}

// ==============================
// CONFIG & HELPERS
// ==============================

// Get value safely from row
function getValue(row, field) {
  return row[field] !== undefined ? row[field] : null;
}

// Parse number safely (handles commas)
function parseNumber(value) {
  if (!value && value !== 0) return null;
  if (typeof value === "number") return value;
  return Number(String(value).replace(/,/g, "")) || null;
}

// Format date safely to YYYY-MM-DD
function formatDate(value) {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(value);
  if (isNaN(date)) return null;
  return date.toISOString().split("T")[0];
}

// Get Supabase SERVICE_ROLE_KEY from Script Properties
function getSupabaseKey() {
  const key = PropertiesService.getScriptProperties().getProperty("SERVICE_ROLE_KEY");
  if (!key) throw new Error("Supabase SERVICE_ROLE_KEY not found in Script Properties");
  return key;
}

// Call Supabase RPC
function callSupabaseRPC(functionName, payload) {
  const url = PropertiesService.getScriptProperties().getProperty("SUPABASE_URL") + "/rest/v1/rpc/" + functionName;
  const options = {
    method: "post",
    contentType: "application/json",
    headers: {
      apikey: getSupabaseKey(),
      Authorization: "Bearer " + getSupabaseKey()
    },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  };
  const response = UrlFetchApp.fetch(url, options);
  const code = response.getResponseCode();
  const text = response.getContentText();

  if (code >= 400) throw new Error("Supabase RPC Error " + code + ": " + text);
  return JSON.parse(text || "{}");
}

// ==============================
// CLIENT INSERT
// ==============================
function insertClient(row) {
  if (!row) throw new Error("Row data is missing");

  const payload = {
    p_client_code: getValue(row, "client_code"),
    p_client_name: getValue(row, "client_name"),
    p_phone: getValue(row, "phone"),
    p_dob: formatDate(getValue(row, "dob")),
    p_email: getValue(row, "email"),
    p_profession: getValue(row, "profession"),
    p_address: getValue(row, "address"),
    p_id_type: getValue(row, "id_type"),
    p_id_number: getValue(row, "id_number")
  };

  // Validate required fields
  if (!payload.p_client_code) throw new Error("Client code is required");
  if (!payload.p_client_name) throw new Error("Client name is required");

  // Call Supabase RPC
  callSupabaseRPC("sp_insert_client", payload);
}

// ==============================
// BOOKING INSERT
// ==============================
function insertBooking(row) {
  if (!row) throw new Error("Row data is missing");

  const payload = {
    p_booking_code: getValue(row, "booking_code"),
    p_project_name: getValue(row, "project_name"),
    p_unit_number: getValue(row, "unit_number"),
    p_client_code: getValue(row, "client_code"),
    p_booking_date: formatDate(getValue(row, "booking_date")),
    p_booking_price: parseNumber(getValue(row, "booking_price")),
    p_threshold: parseNumber(getValue(row, "agreement_threshold_amount")),
    p_schedule_template: getValue(row, "schedule_template"),
    p_booked_by: getValue(row, "booked_by"),
    p_remarks: getValue(row, "remarks") || ""
  };

  if (!payload.p_booking_code) throw new Error("Booking code is required");
  if (!payload.p_client_code) throw new Error("Client code is required");
  if (!payload.p_booking_price) throw new Error("Booking price is required");

  callSupabaseRPC("sp_create_booking", payload);
}

// ==============================
// PAYMENT INSERT
// ==============================
function insertPayment(row) {
  if (!row) throw new Error("Row data is missing");

  const payload = {
    p_booking_code: getValue(row, "booking_code"),
    p_instalment_no: parseNumber(getValue(row, "instalment_no")) || null,
    p_receipt_no: getValue(row, "receipt_no"),
    p_payment_date: formatDate(getValue(row, "payment_date")),
    p_amount: parseNumber(getValue(row, "amount")),
    p_basic_amount: parseNumber(getValue(row, "basic_amount")),
    p_gst: parseNumber(getValue(row, "gst_amount")),
    p_mode: getValue(row, "payment_mode")?.toString().trim() || null,
    p_payment_type: getValue(row, "payment_type")?.toString().trim() || null,
    p_bank: getValue(row, "bank_name")?.toString().trim() || null,
    p_remarks: getValue(row, "remarks")?.toString().trim() || ""
  };

  // Validate required fields
  if (!payload.p_booking_code) throw new Error("Booking code is required");
  if (!payload.p_receipt_no) throw new Error("Receipt number is required");
  if (!payload.p_payment_date) throw new Error("Payment date is required");
  if (!payload.p_amount) throw new Error("Amount is required");

  // Call Supabase RPC — exact function name
  callSupabaseRPC("sp_insert_payment", payload);
}

// ==============================
// MAIN FORM SUBMIT TRIGGER
// ==============================
function handleFormSubmit(e) {
  if (!e) return;

  const sheet = e.range.getSheet();
  const sheetName = sheet.getName();
  const headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
  const submitCol = headers.indexOf("submit") + 1;
  if (submitCol === 0) throw new Error("Submit column not found");

  // Only run if submit checkbox ticked
  if (e.range.getColumn() !== submitCol) return;
  if (e.value !== "TRUE") return;

  const rowIndex = e.range.getRow();
  const rowValues = sheet.getRange(rowIndex, 1, 1, sheet.getLastColumn()).getValues()[0];

  const row = {};
  headers.forEach((header, i) => {
    row[header] = rowValues[i];
  });

  try {
    switch (sheetName) {
      case "Clients_Responses":
        insertClient(row);
        break;
      case "Bookings_Responses":
        insertBooking(row);
        break;
      case "Payments_Responses":
        insertPayment(row);
        break;
      default:
        throw new Error("Unknown sheet: " + sheetName);
    }

    // Success → uncheck submit and update status/message
    sheet.getRange(rowIndex, submitCol).setValue(false);
    const statusCol = headers.indexOf("system_status") + 1;
    const msgCol = headers.indexOf("system_message") + 1;
    if (statusCol > 0) sheet.getRange(rowIndex, statusCol).setValue("SUCCESS");
    if (msgCol > 0) sheet.getRange(rowIndex, msgCol).setValue("Row inserted successfully");

  } catch (err) {
    Logger.log("Error processing row " + rowIndex + ": " + err.message);
    const statusCol = headers.indexOf("system_status") + 1;
    const msgCol = headers.indexOf("system_message") + 1;
    if (statusCol > 0) sheet.getRange(rowIndex, statusCol).setValue("ERROR");
    if (msgCol > 0) sheet.getRange(rowIndex, msgCol).setValue(err.message);

    SpreadsheetApp.getUi().alert("Error: " + err.message);
  }
}

/* ============================= */
/* DAILY PAYMENT REMINDERS       */
/* ============================= */

function runPaymentReminders() {

  const reminders = callSupabaseRPC("sp_get_due_reminders", {});

  if (!reminders || reminders.length === 0) {
    Logger.log("No reminders today");
    return;
  }

  reminders.forEach(rem => {

    if (!rem.email) return;

    const formattedAmount = Number(rem.demand_amount)
      .toLocaleString("en-IN", { minimumFractionDigits: 2 });

    const subject = `Payment Reminder - Instalment ${rem.instalment_no}`;

    const body =
      `Dear ${rem.client_name},\n\n` +
      `This is a reminder that your instalment ${rem.instalment_no} ` +
      `for booking ${rem.booking_code} of amount ₹${formattedAmount} ` +
      `is due on ${rem.due_date}.\n\n` +
      `Please ignore if already paid.\n\n` +
      `Thank you.`;

    MailApp.sendEmail(rem.email, subject, body);

    callSupabaseRPC("sp_mark_reminder_sent", {
      p_schedule_id: rem.schedule_id
    });

  });
}

/* ============================= */
/* DAILY BIRTHDAY EMAILS         */
/* ============================= */

function runBirthdayEmails() {

  const birthdays = callSupabaseRPC("sp_get_today_birthdays", {});

  if (!birthdays || birthdays.length === 0) {
    Logger.log("No birthdays today");
    return;
  }

  birthdays.forEach(c => {

    if (!c.email) return;

    const subject = "Happy Birthday from Our Team!";

    const body =
      `Dear ${c.client_name},\n\n` +
      `Wishing you a very Happy Birthday! 🎉\n\n` +
      `Warm regards,\nAuspire Team`;

    MailApp.sendEmail(c.email, subject, body);

  });
}

function parseNumber(value) {
  if (!value) return 0;

  if (typeof value === "number") return value;

  // Remove commas if any
  value = value.toString().replace(/,/g, "");

  return parseFloat(value) || 0;
}

function bulkUploadScheduleTemplates() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName("Schedule_Templates_Import");
  if (!sheet) throw new Error("Sheet 'Schedule_Templates_Import' not found");

  const data = sheet.getRange(2, 1, sheet.getLastRow() - 1, sheet.getLastColumn()).getValues();
  const headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];

  data.forEach((rowValues, index) => {
    const row = {};
    headers.forEach((header, i) => {
      row[header] = [rowValues[i]];
    });

    const payload = {
      p_template_name: getValue(row, "template_name")?.toString().trim(),
      p_instalment_no: parseNumber(getValue(row, "instalment_no")),
      p_milestone_name: getValue(row, "milestone_name")?.toString().trim(),
      p_percentage: parseNumber(getValue(row, "percentage"))
    };

    try {
      callSupabaseRPC("sp_insert_schedule_template", payload);
      Logger.log(`Row ${index + 2} inserted successfully: ${payload.p_template_name} - instalment ${payload.p_instalment_no}`);
    } catch (err) {
      Logger.log(`Error inserting row ${index + 2}: ${err.message}`);
    }
  });

  SpreadsheetApp.getUi().alert("Bulk upload completed. Check logs for details.");
}