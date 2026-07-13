// Headless smoke test: boot the *bundled* Ruby server (as the packaged app
// would) and confirm GET /health returns 200. Run on each OS in CI before
// packaging so a broken bundled runtime fails fast, independent of the GUI.
const fs = require('fs')
const os = require('os')
const path = require('path')
const { pickFreePort, startServer, waitForHealth, stopServer, rubyBinName } = require('../src/server')

const DESKTOP_DIR = path.resolve(__dirname, '..')
const APP_DIR = path.resolve(DESKTOP_DIR, '..') // repo root — where desktop_boot.rb lives
const RUBY_BIN = path.join(DESKTOP_DIR, 'vendor', 'ruby', 'bin', rubyBinName())

async function main() {
  if (!fs.existsSync(RUBY_BIN)) {
    console.error(`SMOKE FAIL: bundled Ruby not found at ${RUBY_BIN} — run build:ruby first`)
    process.exit(1)
  }
  // Launch exactly like the packaged app: absolute bundled-Ruby path, no Bundler shim.
  const launcher = (appDir) => ({ cmd: RUBY_BIN, args: [path.join(appDir, 'desktop_boot.rb')] })
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ss-smoke-'))
  let child = null
  try {
    const port = await pickFreePort()
    child = startServer({
      appDir: APP_DIR, dataDir, sessionSecret: 'smoke-secret', port,
      launcher, logStream: process.stdout
    })
    await waitForHealth(port, { timeoutMs: 60000 })
    console.log('SMOKE OK: /health returned 200')
  } finally {
    if (child) await stopServer(child)
    fs.rmSync(dataDir, { recursive: true, force: true })
  }
}

main().catch((err) => {
  console.error('SMOKE FAIL:', err && err.message ? err.message : err)
  process.exit(1)
})
