const net = require('net')
const http = require('http')
const os = require('os')
const path = require('path')
const { spawn } = require('child_process')

// Resolve a free TCP port on the loopback interface.
function pickFreePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer()
    srv.unref()
    srv.on('error', reject)
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address()
      srv.close(() => resolve(port))
    })
  })
}

// Argv to launch the Ruby server in development (through Bundler).
// The packaged app injects a different launcher (bundled Ruby) via startServer.
function rubyLauncher(appDir) {
  return { cmd: 'bundle', args: ['exec', 'ruby', path.join(appDir, 'desktop_boot.rb')] }
}

// A GUI/desktop launch context (or a shell without the version manager activated)
// often lacks the PATH entries that make `ruby`/`bundle` resolvable — e.g. mise,
// rbenv, asdf, or rvm shims — which surfaces as `spawn bundle ENOENT`. Prepend the
// common ones so spawn() can find them. The packaged app uses an absolute
// bundled-Ruby path and does not rely on this.
function augmentedPath() {
  const home = os.homedir()
  const extra = [
    path.join(home, '.local/share/mise/shims'),
    path.join(home, '.local/bin'),
    path.join(home, '.rbenv/shims'),
    path.join(home, '.asdf/shims'),
    path.join(home, '.rvm/bin'),
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/bin',
    '/bin'
  ]
  return [...extra, process.env.PATH || ''].filter(Boolean).join(path.delimiter)
}

// Basename of the Ruby executable for a platform. Windows ships ruby.exe;
// macOS/Linux ship ruby. Used to locate the bundled Ruby in the packaged app.
function rubyBinName(platform = process.platform) {
  return platform === 'win32' ? 'ruby.exe' : 'ruby'
}

// Spawn the Ruby/Puma server. Returns the ChildProcess.
function startServer({ appDir, dataDir, sessionSecret, port, logStream, launcher = rubyLauncher }) {
  const { cmd, args } = launcher(appDir)
  const child = spawn(cmd, args, {
    cwd: appDir,
    env: {
      ...process.env,
      PATH: augmentedPath(),
      PORT: String(port),
      DATA_DIR: dataDir,
      SESSION_SECRET: sessionSecret,
      RACK_ENV: 'production'
    }
  })
  if (logStream) {
    child.stdout.pipe(logStream)
    child.stderr.pipe(logStream)
  }
  return child
}

// Poll GET /health until 200 or the timeout elapses.
function waitForHealth(port, { timeoutMs = 30000, intervalMs = 200 } = {}) {
  const deadline = Date.now() + timeoutMs
  return new Promise((resolve, reject) => {
    const retry = () => {
      if (Date.now() > deadline) return reject(new Error('server did not become healthy in time'))
      setTimeout(tick, intervalMs)
    }
    const tick = () => {
      const req = http.get({ host: '127.0.0.1', port, path: '/health', timeout: 1000 }, (res) => {
        res.resume()
        if (res.statusCode === 200) resolve()
        else retry()
      })
      req.on('error', retry)
      req.on('timeout', () => { req.destroy(); retry() })
    }
    tick()
  })
}

// Gracefully stop the server child (SIGTERM, then SIGKILL after a grace period).
function stopServer(child) {
  return new Promise((resolve) => {
    if (!child || child.exitCode !== null || child.signalCode !== null) return resolve()
    let done = false
    let killTimer = null
    const finish = () => {
      if (done) return
      done = true
      if (killTimer) clearTimeout(killTimer)
      resolve()
    }
    child.once('exit', finish)
    child.once('error', finish) // a child that never spawned emits 'error', not 'exit'
    if (process.platform === 'win32') {
      spawn('taskkill', ['/pid', String(child.pid), '/T', '/F'])
    } else {
      child.kill('SIGTERM')
      killTimer = setTimeout(() => { if (!done) child.kill('SIGKILL') }, 5000)
    }
  })
}

module.exports = { pickFreePort, rubyLauncher, startServer, waitForHealth, stopServer, rubyBinName }
