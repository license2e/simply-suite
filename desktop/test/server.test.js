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

test('server boots, answers /health, and stops', async () => {
  const port = await pickFreePort()
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ss-serv-'))
  const child = startServer({ appDir: APP_DIR, dataDir, sessionSecret: 'test-secret', port })
  try {
    await waitForHealth(port, { timeoutMs: 30000 })
  } finally {
    await stopServer(child)
    fs.rmSync(dataDir, { recursive: true, force: true })
  }
})
