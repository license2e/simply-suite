const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { defaultDataDir, isDataFolder, resolveTarget, initializeDataFolder, DATA_SUBFOLDER, MARKER } = require('../src/data-dir')

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'ss-datadir-'))

test('defaultDataDir nests a data/ folder under userData', () => {
  assert.strictEqual(defaultDataDir('/u/x'), path.join('/u/x', 'data'))
})

test('initializeDataFolder writes the marker and isDataFolder detects it', () => {
  const d = path.join(tmp(), 'store')
  initializeDataFolder(d)
  assert.ok(fs.existsSync(path.join(d, MARKER)))
  assert.strictEqual(isDataFolder(d), true)
})

test('resolveTarget nests a subfolder for a plain parent, uses SS folder in place', () => {
  const parent = tmp()
  assert.strictEqual(resolveTarget(parent), path.join(parent, DATA_SUBFOLDER))
  const existing = path.join(tmp(), 'store')
  initializeDataFolder(existing)
  assert.strictEqual(resolveTarget(existing), existing)
})

test('initializeDataFolder does not overwrite an existing marker', () => {
  const d = path.join(tmp(), 'store')
  initializeDataFolder(d)
  const markerPath = path.join(d, MARKER)
  const custom = JSON.stringify({ app: 'simply-suite', schema: 1, sentinel: 'keep-me' })
  fs.writeFileSync(markerPath, custom)
  initializeDataFolder(d) // second call must be non-destructive
  assert.strictEqual(fs.readFileSync(markerPath, 'utf8'), custom)
})

test('initializeDataFolder writes marker content {app, schema}', () => {
  const d = path.join(tmp(), 'store')
  initializeDataFolder(d)
  const marker = JSON.parse(fs.readFileSync(path.join(d, MARKER), 'utf8'))
  assert.deepStrictEqual(marker, { app: 'simply-suite', schema: 1 })
})
