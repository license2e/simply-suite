const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { loadSettings, saveSettings, getOrCreateSessionSecret } = require('../src/settings')

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'ss-settings-'))

test('loadSettings returns {} when nothing is saved', () => {
  assert.deepStrictEqual(loadSettings(tmp()), {})
})

test('saveSettings then loadSettings round-trips', () => {
  const d = tmp()
  saveSettings(d, { dataDir: '/some/path' })
  assert.strictEqual(loadSettings(d).dataDir, '/some/path')
})

test('getOrCreateSessionSecret is stable across calls', () => {
  const d = tmp()
  const a = getOrCreateSessionSecret(d)
  const b = getOrCreateSessionSecret(d)
  assert.strictEqual(a, b)
  assert.match(a, /^[0-9a-f]{128}$/)
})
