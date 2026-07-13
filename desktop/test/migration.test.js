const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { verifyCopy, migrate } = require('../src/migration')

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'ss-migrate-'))

test('verifyCopy: ok for an identical tree, not-ok for a mutated file', () => {
  const a = tmp(); const b = tmp()
  fs.writeFileSync(path.join(a, 'f.txt'), 'data')
  fs.writeFileSync(path.join(b, 'f.txt'), 'data')
  assert.deepStrictEqual(verifyCopy(a, b), { ok: true })
  fs.writeFileSync(path.join(b, 'f.txt'), 'DATA')
  assert.strictEqual(verifyCopy(a, b).ok, false)
})

test('migrate copies data to newDir and removes oldDir', () => {
  const old = tmp(); const parent = tmp()
  const nw = path.join(parent, 'Simply Suite')
  fs.mkdirSync(path.join(old, 'invoices'), { recursive: true })
  fs.writeFileSync(path.join(old, 'invoices', 'a.json'), '{"n":1}')
  migrate(old, nw)
  assert.strictEqual(fs.existsSync(old), false)
  assert.strictEqual(fs.readFileSync(path.join(nw, 'invoices', 'a.json'), 'utf8'), '{"n":1}')
})

test('migrate throws and preserves oldDir when the destination cannot be written', () => {
  const old = tmp()
  fs.writeFileSync(path.join(old, 'f.txt'), 'x')
  // A file where the destination directory should go → copyTree mkdir fails.
  const clash = path.join(tmp(), 'blocker')
  fs.writeFileSync(clash, 'i am a file, not a dir')
  const dest = path.join(clash, 'inside')
  assert.throws(() => migrate(old, dest))
  assert.strictEqual(fs.existsSync(path.join(old, 'f.txt')), true)
})
