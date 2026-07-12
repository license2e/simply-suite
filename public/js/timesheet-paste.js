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
