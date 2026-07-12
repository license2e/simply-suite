# Timesheet Paste-Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user paste a copied spreadsheet/CSV range onto the timesheet grid and have it expand into editable rows, with no server changes.

**Architecture:** A pure client-side ESM module (`public/js/timesheet-paste.js`) parses the tab-separated clipboard text into normalized row objects; the existing Stimulus `TimesheetController` (inline in `views/admin/layout-default.erb`) imports it and, on a multi-cell `paste`, fills empty rows then clones the row template. Rows use the same `entries[i][field]` inputs, so the existing bulk-save (`POST /timesheets/:client_key` → `parse_rows` → `TimesheetPeriod#apply`) persists them and re-buckets by date. No Ruby, routes, or gems change.

**Tech Stack:** Vanilla ESM + Stimulus 3 (vendored at `public/js/stimulus.js`, no build step) · Node's built-in test runner (`node:test`, zero-dependency) for the parse module · ferrum (already a gem) for a headless-Chrome wiring check.

**Spec:** `docs/superpowers/specs/2026-07-11-timesheet-paste-import-design.md` (read it first).

## Global Constraints

- **Client-side only.** No new routes, models, Ruby code, or gems. The existing bulk-save path persists pasted rows unchanged.
- **No build step.** Browser-facing JS is plain ESM served from `public/js/` via the existing `/js` `Rack::Static` route.
- **Column order is fixed:** `Date · Item · Description · Qty · Rate` (positional). A header row (first cell not a date) is skipped.
- **Date output format:** `MM/DD/YYYY` (accept `MM/DD/YYYY`, `M/D/YYYY`, `YYYY-MM-DD`; leave anything else as-is). **Rate:** strip everything except digits and `.`.
- **Append behavior:** fill empty editable rows first, then append cloned rows. Never touch invoiced (disabled) rows. Nothing persists until the user clicks Save.
- **Single-value paste is untouched:** only intercept when the clipboard text contains a tab or newline.
- Commit messages end with: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## File Structure

**New:**
- `public/js/timesheet-paste.js` — pure parser: `parseClipboard(text)` + `normalizeDate`/`normalizeRate`/`looksLikeDate`. Browser ESM; no DOM, no imports.
- `public/js/timesheet-paste.test.mjs` — Node `node:test` unit tests for the parser.
- `public/js/package.json` — `{"type":"module"}` so Node treats the `.js` module as ESM (harmless to the browser; nothing requests it).

**Modified:**
- `views/admin/layout-default.erb` — import `parseClipboard`; add `pasteRows` + helper methods to `TimesheetController`.
- `views/timesheets/show.erb` — add `data-action="paste->timesheet#pasteRows"` to the timesheet `<form>`; add the discoverability hint.

---

## Task 1: Pure clipboard parser + Node unit tests

**Files:**
- Create: `public/js/timesheet-paste.js`
- Create: `public/js/timesheet-paste.test.mjs`
- Create: `public/js/package.json`

**Interfaces:**
- Produces (imported by Task 2):
  - `parseClipboard(text: string) -> Array<{ date, item, desc, qty, rate }>` — each value a normalized string; header row skipped; `[]` for empty/whitespace input.
  - `normalizeDate(s) -> string` · `normalizeRate(s) -> string` · `looksLikeDate(s) -> boolean` (exported for direct testing).

- [ ] **Step 1: Create `public/js/package.json`**

```json
{ "type": "module", "private": true }
```

- [ ] **Step 2: Write the failing tests**

```javascript
// public/js/timesheet-paste.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseClipboard, normalizeDate, normalizeRate, looksLikeDate } from './timesheet-paste.js';

test('normalizeDate handles US + ISO, zero-pads, leaves unknown as-is', () => {
  assert.equal(normalizeDate('7/5/2026'), '07/05/2026');
  assert.equal(normalizeDate('07/05/2026'), '07/05/2026');
  assert.equal(normalizeDate('2026-07-05'), '07/05/2026');
  assert.equal(normalizeDate('2026-7-5'), '07/05/2026');
  assert.equal(normalizeDate('July 5'), 'July 5');
  assert.equal(normalizeDate(''), '');
});

test('normalizeRate strips $, commas, and stray text', () => {
  assert.equal(normalizeRate('$1,250.00'), '1250.00');
  assert.equal(normalizeRate('125'), '125');
  assert.equal(normalizeRate('  '), '');
});

test('looksLikeDate recognizes only US + ISO date shapes', () => {
  assert.equal(looksLikeDate('7/5/2026'), true);
  assert.equal(looksLikeDate('2026-07-05'), true);
  assert.equal(looksLikeDate('Date'), false);
  assert.equal(looksLikeDate(''), false);
});

test('parseClipboard maps columns positionally and skips a header row', () => {
  const tsv = 'Date\tItem\tDescription\tQty\tRate\n7/5/2026\tDev\tBuild API\t3\t$125\n2026-07-06\tDesign\tMockups\t2\t100';
  const rows = parseClipboard(tsv);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[0], { date: '07/05/2026', item: 'Dev', desc: 'Build API', qty: '3', rate: '125' });
  assert.deepEqual(rows[1], { date: '07/06/2026', item: 'Design', desc: 'Mockups', qty: '2', rate: '100' });
});

test('parseClipboard keeps a first row that starts with a date (no header)', () => {
  const rows = parseClipboard('7/5/2026\tDev\tx\t1\t50');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].date, '07/05/2026');
});

test('parseClipboard fills missing trailing columns and ignores extras', () => {
  assert.deepEqual(parseClipboard('7/5/2026\tDev\tx')[0],
                   { date: '07/05/2026', item: 'Dev', desc: 'x', qty: '', rate: '' });
  assert.deepEqual(parseClipboard('7/5/2026\tDev\tx\t1\t50\tEXTRA')[0],
                   { date: '07/05/2026', item: 'Dev', desc: 'x', qty: '1', rate: '50' });
});

test('parseClipboard handles CRLF and trailing blank lines; empty -> []', () => {
  assert.equal(parseClipboard('7/5/2026\tDev\tx\t1\t50\r\n\r\n').length, 1);
  assert.deepEqual(parseClipboard(''), []);
  assert.deepEqual(parseClipboard('   \n  '), []);
});
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `node --test public/js/timesheet-paste.test.mjs`
Expected: FAIL — `Cannot find module '.../timesheet-paste.js'`.

- [ ] **Step 4: Implement `public/js/timesheet-paste.js`**

```javascript
// public/js/timesheet-paste.js
// Pure helpers for turning a spreadsheet/CSV clipboard paste (tab-separated)
// into normalized timesheet rows. No DOM, no imports — unit-tested in isolation.

const pad = (n) => String(n).padStart(2, '0');

export function looksLikeDate(s) {
  const v = String(s ?? '').trim();
  return /^\d{1,2}\/\d{1,2}\/\d{4}$/.test(v) || /^\d{4}-\d{1,2}-\d{1,2}$/.test(v);
}

export function normalizeDate(s) {
  const v = String(s ?? '').trim();
  let m;
  if ((m = v.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/))) return `${pad(m[1])}/${pad(m[2])}/${m[3]}`;
  if ((m = v.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/)))   return `${pad(m[2])}/${pad(m[3])}/${m[1]}`;
  return v; // unrecognized — leave as pasted so the user can fix it
}

export function normalizeRate(s) {
  return String(s ?? '').replace(/[^\d.]/g, '');
}

export function parseClipboard(text) {
  const lines = String(text ?? '').replace(/\r\n?/g, '\n').split('\n');
  while (lines.length && lines[lines.length - 1].trim() === '') lines.pop();
  if (lines.length === 0) return [];

  // Header detection: if the first line's first cell isn't a date, drop it.
  if (!looksLikeDate(lines[0].split('\t')[0])) lines.shift();

  return lines
    .filter((line) => line.trim() !== '')
    .map((line) => {
      const c = line.split('\t');
      return {
        date: normalizeDate(c[0] ?? ''),
        item: String(c[1] ?? '').trim(),
        desc: String(c[2] ?? '').trim(),
        qty:  String(c[3] ?? '').trim(),
        rate: normalizeRate(c[4] ?? ''),
      };
    });
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `node --test public/js/timesheet-paste.test.mjs`
Expected: PASS — all tests green (`# pass 7`, `# fail 0`).

- [ ] **Step 6: Commit**

```bash
git add public/js/timesheet-paste.js public/js/timesheet-paste.test.mjs public/js/package.json
git commit -m "feat: add clipboard TSV parser for timesheet paste-import

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Wire the paste handler into the grid + view

**Files:**
- Modify: `views/admin/layout-default.erb` (import `parseClipboard`; add `pasteRows` + helpers to `TimesheetController`)
- Modify: `views/timesheets/show.erb` (form `data-action` + hint)
- Create (verification only): `scripts/verify_timesheet_paste.rb`

**Interfaces:**
- Consumes: `parseClipboard(text)` from Task 1 (`/js/timesheet-paste.js`).
- Consumes (existing `TimesheetController` members): `bodyTarget`, `rowTemplateTarget`, `rowIndex`, `updateAllTotals()`.

- [ ] **Step 1: Add the module import** in `views/admin/layout-default.erb`

Find:
```erb
    import { Application, Controller } from '/js/stimulus.js';
```
Add the parser import right after it:
```erb
    import { Application, Controller } from '/js/stimulus.js';
    import { parseClipboard } from '/js/timesheet-paste.js';
```

- [ ] **Step 2: Add `pasteRows` + helpers to `TimesheetController`**

In `views/admin/layout-default.erb`, inside `class TimesheetController extends Controller { … }`, add these methods (place them after `addRow`):

```javascript
      pasteRows(event) {
        const text = event.clipboardData ? event.clipboardData.getData('text') : '';
        // Only intercept a spreadsheet range; a single value pastes normally.
        if (!/[\t\n]/.test(text)) return;
        const rows = parseClipboard(text);
        if (rows.length === 0) return;
        event.preventDefault();
        rows.forEach((r) => this._fillOrAddRow(r));
        this.updateAllTotals();
      }

      _fillOrAddRow(r) {
        let row = this._emptyEditableRow();
        if (!row) {
          const html = this.rowTemplateTarget.innerHTML.replace(/ROW_INDEX/g, this.rowIndex++);
          this.bodyTarget.insertAdjacentHTML('beforeend', html);
          row = this.bodyTarget.querySelector('[data-ts-row]:last-of-type');
        }
        this._setRowValue(row, 'service_date', r.date);
        this._setRowValue(row, 'item', r.item);
        this._setRowValue(row, 'desc', r.desc);
        this._setRowValue(row, 'qty', r.qty);
        this._setRowValue(row, 'cost', r.rate);
      }

      _setRowValue(row, field, value) {
        const el = row.querySelector(`[name$="[${field}]"]`);
        if (el && !el.disabled) el.value = value;
      }

      _emptyEditableRow() {
        const fields = ['service_date', 'item', 'desc', 'qty', 'cost'];
        return Array.from(this.bodyTarget.querySelectorAll('[data-ts-row]')).find((row) => {
          const id = row.querySelector('[name$="[id]"]');
          if (id && id.disabled) return false; // invoiced rows are disabled
          return fields.every((f) => {
            const el = row.querySelector(`[name$="[${f}]"]`);
            return !el || el.value.trim() === '';
          });
        });
      }
```

Note: pasted rate overrides a template's default-rate value because `_setRowValue` is called for `cost`; a blank pasted rate (`r.rate === ''`) sets the field to empty. If you prefer a blank paste to keep the template default, guard with `if (value !== '')` inside `_setRowValue` — but the spec's positional mapping treats an empty Rate cell as empty, so set it unconditionally.

- [ ] **Step 3: Bind the action + add the hint** in `views/timesheets/show.erb`

Find the form open tag:
```erb
  <form action="/timesheets/<%= @client.slug %>?period=<%= @period.key %>" method="post" data-timesheet-target="form">
```
Add the paste action:
```erb
  <form action="/timesheets/<%= @client.slug %>?period=<%= @period.key %>" method="post" data-timesheet-target="form" data-action="paste->timesheet#pasteRows">
```

Then find the Add Row / Save button row:
```erb
    <div class="flex items-center justify-between mt-3">
      <button type="button" data-action="timesheet#addRow"
        class="px-3 py-2 bg-white border border-gray-300 hover:border-slate-500 text-xs font-medium rounded transition-colors cursor-pointer">
        + Add Row
      </button>
      <button type="submit"
        class="px-5 py-2 bg-slate-700 hover:bg-slate-800 text-white text-sm font-medium rounded-md transition-colors cursor-pointer">
        Save
      </button>
    </div>
```
Add the hint immediately after that closing `</div>`:
```erb
    <p class="text-xs text-gray-400 mt-2">Tip: copy rows from a spreadsheet (Date · Item · Description · Qty · Rate) and paste (⌘/Ctrl+V) here.</p>
```

- [ ] **Step 4: Rebuild Tailwind** (the hint uses existing utility classes, but rebuild so any new class is emitted)

Run: `./tailwindcss -i public/css/input.css -o public/css/tailwind.css`
Expected: `Done in NNms`.

- [ ] **Step 5: Write the headless-Chrome verification** `scripts/verify_timesheet_paste.rb`

This boots a throwaway app on a temp port with a temp `DATA_DIR` (mirroring `scripts/generate_invoice_screenshot.rb`), navigates to a client's timesheet, dispatches a synthetic `paste` with a TSV block (header + mixed date formats + a `$`/comma rate), and asserts the resulting rows.

```ruby
# scripts/verify_timesheet_paste.rb — headless-Chrome wiring check for paste-import.
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'store'
require 'tmpdir'
require 'rack'
require 'puma'
require 'puma/configuration'
require 'puma/launcher'
require 'net/http'
require 'ferrum'

PORT = 9466
Store.data_root = Dir.mktmpdir('paste-verify')
biz = Store::Business.create(name: 'Verify Co', contact: 'C', email: 'v@x.com',
                             street: '1', city: 'CLT', state: 'NC', zip: '28203')
client = biz.create_client(name: 'Paste Client', prefix: 'PC', contact: 'x', email: 'p@x.com',
                           street: '1', street2: '', city: 'CLT', state: 'NC', zip: '28203')

ENV['RACK_ENV'] = 'development'
ENV['DATA_DIR'] = Store.data_root
app = Rack::Builder.parse_file(File.expand_path('../config.ru', __dir__))
app = app.first if app.is_a?(Array)
conf = Puma::Configuration.new { |c| c.bind "tcp://127.0.0.1:#{PORT}"; c.app app; c.silence_single_worker_warning rescue nil }
launcher = Puma::Launcher.new(conf)
Thread.new { launcher.run }
# wait for boot
20.times { (Net::HTTP.get_response(URI("http://127.0.0.1:#{PORT}/businesses")) rescue nil) && break; sleep 0.25 }

tsv = "Date\tItem\tDescription\tQty\tRate\n7/5/2026\tDev\tBuild API\t3\t$1,250.00\n2026-07-06\tDesign\tMockups\t2\t100"
browser = Ferrum::Browser.new(headless: true, browser_options: { 'no-sandbox': nil }, timeout: 20)
begin
  browser.goto("http://127.0.0.1:#{PORT}/businesses")
  browser.at_css("form[action=\"/businesses/#{biz.slug}/select\"] button")&.click
  browser.network.wait_for_idle rescue nil
  browser.goto("http://127.0.0.1:#{PORT}/timesheets/#{client.slug}")
  sleep 0.7
  browser.execute(<<~JS)
    const form = document.querySelector('form[data-timesheet-target="form"]');
    const dt = new DataTransfer();
    dt.setData('text', #{tsv.dump});
    form.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
  JS
  sleep 0.4
  rows = browser.evaluate(<<~JS)
    Array.from(document.querySelectorAll('tbody [data-ts-row]')).map(r => ({
      date: r.querySelector('[name$="[service_date]"]')?.value,
      item: r.querySelector('[name$="[item]"]')?.value,
      desc: r.querySelector('[name$="[desc]"]')?.value,
      qty:  r.querySelector('[name$="[qty]"]')?.value,
      cost: r.querySelector('[name$="[cost]"]')?.value,
    }))
  JS
  require 'pp'; pp rows
  ok = rows.length == 2 &&
       rows[0].values_at('date','item','desc','qty','cost') == ['07/05/2026','Dev','Build API','3','1250.00'] &&
       rows[1].values_at('date','item','desc','qty','cost') == ['07/06/2026','Design','Mockups','2','100']
  puts(ok ? 'RESULT: PASS — pasted range expanded into normalized rows ✓' : 'RESULT: FAIL')
  exit(ok ? 0 : 1)
ensure
  browser.quit
  launcher.stop rescue nil
end
```

- [ ] **Step 6: Run the verification**

Run: `bundle exec ruby scripts/verify_timesheet_paste.rb`
Expected: prints the two parsed rows and `RESULT: PASS — pasted range expanded into normalized rows ✓` (exit 0). If Chrome ignores the synthetic `clipboardData` (older builds), the parser is already covered by Task 1's unit tests — in that case confirm the wiring by asserting the form carries `data-action="paste->timesheet#pasteRows"` and that `pasteRows` runs (e.g. temporarily log inside it), and note it in the report.

- [ ] **Step 7: Confirm the existing suite is unaffected**

Run: `bundle exec rspec`
Expected: 52 examples, 0 failures (no Ruby changed; this is a regression guard).

- [ ] **Step 8: Commit**

```bash
git add views/admin/layout-default.erb views/timesheets/show.erb scripts/verify_timesheet_paste.rb public/css/tailwind.css
git commit -m "feat: paste spreadsheet rows into the timesheet grid

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

Note: `public/css/tailwind.css` is gitignored, so it won't actually stage — that's fine; the `git add` line is harmless and the built CSS is regenerated by `/dev`. Drop it from the `git add` if it errors.

---

## Notes on ordering & risk

- Task 1 is a self-contained, unit-tested pure module with no dependency on the app — safe to land first and fully covers the parsing/normalization logic (the error-prone part).
- Task 2 is thin DOM wiring on top of the existing `TimesheetController`; the ferrum check confirms the end-to-end paste. Synthetic `ClipboardEvent` with a constructor-supplied `DataTransfer` is supported in current Chrome; the fallback (Step 6) covers older builds.
- No server, route, model, or gem changes. Pasted rows persist through the existing bulk-save + `apply` (including cross-month re-bucketing), already covered by `spec/requests/timesheets_spec.rb`.
