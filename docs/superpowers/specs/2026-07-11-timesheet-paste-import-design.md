# Simply Suite — Paste Timesheet Rows from a Spreadsheet

**Date:** 2026-07-11
**Status:** Approved
**Scope:** Let a user paste a copied range from a spreadsheet (Excel / Google Sheets) or CSV directly onto the timesheet grid, expanding it into editable rows — client-side only, reusing the existing bulk-save path.

---

## Overview

The timesheet grid (`views/timesheets/show.erb` + `_row.erb`, driven by the Stimulus `TimesheetController` in `views/admin/layout-default.erb`) lets a user add rows one at a time. This feature adds a **paste-into-grid** import: copy a range of cells from a spreadsheet and press ⌘/Ctrl+V while focused in the grid, and the rows fill in automatically.

The clipboard produced by a spreadsheet copy is **tab-separated values** (cells joined by `\t`, rows by newline), so parsing is a small client-side step. Nothing new is needed on the server: pasted rows use the same `entries[<index>][field]` inputs as manually-added rows, so the existing bulk-save (`POST /timesheets/:client_key` → `parse_rows` → `TimesheetPeriod#apply`) persists them and re-buckets each row into its own period file by date.

Design decisions (all approved):

1. **Input method:** paste directly onto the grid (not an upload or a separate paste box).
2. **Column layout:** fixed grid order — `Date · Item · Description · Qty · Rate`. A header row is auto-detected and skipped.
3. **Existing rows:** append — pasted rows fill any empty editable rows first, then add new ones; saved/invoiced rows are never touched.
4. **Parsing location:** client-side, in the already-vendored Stimulus (`public/js/stimulus.js`). No new route, no AJAX.

---

## Section 1: Interaction & Data Flow

- Add a `paste` action to the existing `TimesheetController`, bound to the timesheet **`<form>`** element (the one already carrying `data-timesheet-target="form"` in `show.erb`, which wraps the table). Paste events from any input inside the form bubble to it, so `data-action="paste->timesheet#pasteRows"` on the form catches a paste made in any row cell.
- On paste, read `event.clipboardData.getData('text')`.
  - **Multi-cell paste** (the text contains a tab or a newline): `preventDefault()` and expand it into rows (Section 2–3).
  - **Single value** (no tab, no newline): do nothing special — the browser's normal paste into the focused field happens. This preserves pasting one value into one cell.
- After expanding, recalculate row totals (reuse the controller's existing `updateAllTotals` / `_calcRowTotal`).
- **Nothing is persisted on paste.** The rows are populated in the DOM exactly like manual edits; the user reviews and clicks **Save**, which uses the existing `POST /timesheets/:client_key` bulk-save. No server change.
- If pasted rows carry dates in different months than the currently-viewed period, `TimesheetPeriod#apply` re-buckets each into its correct period file on Save — this is the existing behavior and is expected.

---

## Section 2: Column Mapping & Normalization

- Split the clipboard text into lines (on `\r\n` or `\n`), dropping a trailing empty line. Split each line into cells on `\t`.
- Cells map **positionally** to the grid columns, in order: `Date, Item, Description, Qty, Rate`.
  - Fewer than 5 cells: fill from the left; missing trailing columns stay blank.
  - More than 5 cells: ignore the extras.
- **Header detection:** if the first line's Date cell does not parse as a date, treat the entire first line as a header and skip it. (A real data row's first column is a date; a header's is text like "Date".)
- **Date normalization** → `MM/DD/YYYY`, accepting:
  - `MM/DD/YYYY` and `M/D/YYYY` (US, with or without zero-padding)
  - `YYYY-MM-DD` (ISO)
  - An unrecognized date is left **as pasted** (the field is a plain text input) so the user can see and fix it; on Save, `parse_rows` already does `Date.strptime(..., '%m/%d/%Y') rescue nil`, so a bad date becomes `nil` rather than an error.
- **Rate normalization:** strip everything except digits and `.` (removes `$`, thousands `,`). Blank stays blank.
- **Qty:** taken as-is (the Qty input is `type=number`; a non-numeric value is simply ignored by the browser/`to_f` on save).
- **Item / Description:** taken as-is (trimmed of surrounding whitespace).

---

## Section 3: Row Handling

- For each parsed data line, populate a row:
  1. First, reuse any existing **empty, editable** rows (a row whose Date/Item/Description/Qty/Rate are all blank and that is not invoiced), in document order.
  2. When no empty editable row remains, **clone the row template** (`data-timesheet-target="rowTemplate"`) — the same mechanism as "Add Row", with a fresh row index — and append it to the grid body.
- **Invoiced (read-only) rows are never filled or overwritten.**
- A cloned row from the template may carry the client's default rate in its Rate field (existing behavior); a pasted Rate overrides it, and a blank pasted Rate leaves the template's default in place.
- After populating, run `updateAllTotals` so line totals reflect the pasted Qty × Rate.

---

## Section 4: Discoverability

- Add a one-line hint under the grid (near the "Add Row" / "Save" controls):
  > *Copy rows from a spreadsheet (Date · Item · Description · Qty · Rate) and paste here.*
- No new button is required — paste is the affordance. The hint makes it discoverable.

---

## Section 5: Testing

- **Headless-Chrome check** (ferrum, mirroring the existing verification pattern): load a timesheet page, dispatch a synthetic `paste` event whose `clipboardData` holds a small TSV block (including a header row and a mix of date formats), and assert:
  - the header row is skipped;
  - one grid row is created per data line, with Date normalized to `MM/DD/YYYY`, Item/Description/Qty populated, and Rate stripped of `$`/`,`;
  - an existing empty row is reused before new rows are appended;
  - line totals recalculated.
- **The save path is already covered** by `spec/requests/timesheets_spec.rb` (`parse_rows` + `apply`); pasted rows use identical inputs, so no new server-side spec is required. Optionally add a request-spec assertion only if a server change turns out to be needed (it should not).

---

## Out of Scope

- CSV **file upload** and a separate **paste/preview box** (paste-into-grid was chosen).
- **Header-name mapping** and **focused-cell anchoring** (fixed grid order was chosen).
- Excel **serial-number** dates (copy-paste yields formatted dates, not serials).
- Any server-side parsing endpoint or AJAX — the feature is entirely client-side plus the existing bulk-save.

---

## Files Touched

- `views/admin/layout-default.erb` — add the `pasteRows` action + parsing/normalization helpers to `TimesheetController`; bind `data-action="paste->timesheet#pasteRows"` on the grid.
- `views/timesheets/show.erb` — add `data-action="paste->timesheet#pasteRows"` to the timesheet `<form>` element, and the discoverability hint under the grid controls.
- (No Ruby changes expected; no new routes, models, or gems.)
