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

test('parseClipboard maps columns positionally (Date, Item, Qty, Description, Rate) and skips a header row', () => {
  const tsv = 'Date\tItem\tQty\tDescription\tRate\n7/5/2026\tDev\t3\tBuild API\t$125\n2026-07-06\tDesign\t2\tMockups\t100';
  const rows = parseClipboard(tsv);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[0], { date: '07/05/2026', item: 'Dev', qty: '3', desc: 'Build API', rate: '125' });
  assert.deepEqual(rows[1], { date: '07/06/2026', item: 'Design', qty: '2', desc: 'Mockups', rate: '100' });
});

test('parseClipboard keeps a first row that starts with a date (no header)', () => {
  const rows = parseClipboard('7/5/2026\tDev\tx\t1\t50');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].date, '07/05/2026');
});

test('parseClipboard fills missing trailing columns and ignores extras', () => {
  assert.deepEqual(parseClipboard('7/5/2026\tDev\t2')[0],
                   { date: '07/05/2026', item: 'Dev', qty: '2', desc: '', rate: '' });
  assert.deepEqual(parseClipboard('7/5/2026\tDev\t2\tWork\t50\tEXTRA')[0],
                   { date: '07/05/2026', item: 'Dev', qty: '2', desc: 'Work', rate: '50' });
});

test('parseClipboard handles CRLF and trailing blank lines; empty -> []', () => {
  assert.equal(parseClipboard('7/5/2026\tDev\tx\t1\t50\r\n\r\n').length, 1);
  assert.deepEqual(parseClipboard(''), []);
  assert.deepEqual(parseClipboard('   \n  '), []);
});
