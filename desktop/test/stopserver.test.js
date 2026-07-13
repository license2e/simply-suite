const { test } = require('node:test')
const { stopServer } = require('../src/server')

// Pure-Node unit test for stopServer's spawn-failure path. Kept in its own file
// so node:test runs it in a separate process from the real-Puma integration test
// in server.test.js — a failed spawn in the shared process perturbs that test's
// event loop and cancels it intermittently. The graceful SIGTERM stop path is
// exercised by server.test.js's boot/stop test.
test('stopServer resolves even if the child never spawned', async () => {
  const { spawn } = require('child_process')
  const bad = spawn('simply-suite-no-such-binary-xyz', [])
  bad.on('error', () => {}) // swallow ENOENT so it is not an unhandled error
  await stopServer(bad)     // must resolve (not hang) — child emitted 'error', not 'exit'
})
