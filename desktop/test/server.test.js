const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { pickFreePort, startServer, waitForHealth, stopServer } = require('../src/server')

const APP_DIR = path.resolve(__dirname, '..', '..') // repo root

test('pickFreePort resolves a positive integer', async () => {
  const p = await pickFreePort()
  assert.ok(Number.isInteger(p) && p > 0)
})

test('server boots with a shim-less PATH (Electron launch context), answers /health, and stops', async () => {
  const port = await pickFreePort()
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ss-serv-'))
  // Simulate a desktop/GUI launch: strip the version-manager shims from PATH so
  // `bundle`/`ruby` are NOT directly resolvable. startServer's augmentedPath must
  // re-add them, otherwise this fails with `spawn bundle ENOENT`.
  const savedPath = process.env.PATH
  process.env.PATH = '/usr/bin:/bin'
  let child
  try {
    child = startServer({ appDir: APP_DIR, dataDir, sessionSecret: 'test-secret', port })
    await waitForHealth(port, { timeoutMs: 30000 })
  } finally {
    process.env.PATH = savedPath
    if (child) await stopServer(child)
    fs.rmSync(dataDir, { recursive: true, force: true })
  }
})
