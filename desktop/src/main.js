const { app } = require('electron')
const path = require('path')
const fs = require('fs')
const { loadSettings, saveSettings, getOrCreateSessionSecret } = require('./settings')
const { defaultDataDir, initializeDataFolder } = require('./data-dir')
const { pickFreePort, rubyLauncher, startServer, waitForHealth, stopServer } = require('./server')
const { createSplash, closeSplash, createMainWindow } = require('./windows')
const { runOnboarding, showErrorBox } = require('./dialogs')
const { buildMenu } = require('./menu')

// Where the Ruby app lives: bundled under resources/app when packaged,
// otherwise the repo root (two levels up from desktop/src).
const APP_DIR = app.isPackaged
  ? path.join(process.resourcesPath, 'app')
  : path.resolve(__dirname, '..', '..')

let serverChild = null
let mainWindow = null
let currentDataDir = null
let isQuitting = false

// Choose the Ruby launcher: bundled Ruby when packaged, Bundler in dev.
function launcher(appDir) {
  if (app.isPackaged) {
    return {
      cmd: path.join(process.resourcesPath, 'ruby', 'bin', 'ruby'),
      args: [path.join(appDir, 'desktop_boot.rb')]
    }
  }
  return rubyLauncher(appDir)
}

function serverLog() {
  const dir = path.join(app.getPath('userData'), 'logs')
  fs.mkdirSync(dir, { recursive: true })
  return fs.createWriteStream(path.join(dir, 'server.log'), { flags: 'a' })
}

// Boot the Ruby server against `dataDir`; returns its base URL.
async function bootServer(dataDir) {
  const sessionSecret = getOrCreateSessionSecret(app.getPath('userData'))
  const port = await pickFreePort()
  serverChild = startServer({ appDir: APP_DIR, dataDir, sessionSecret, port, logStream: serverLog(), launcher })
  await waitForHealth(port)
  currentDataDir = dataDir
  return `http://127.0.0.1:${port}/`
}

// Resolve the data folder: use the saved one, or run first-run onboarding.
async function resolveDataDir() {
  const userData = app.getPath('userData')
  const settings = loadSettings(userData)
  if (settings.dataDir) return settings.dataDir

  const chosen = await runOnboarding(defaultDataDir(userData))
  if (!chosen) { app.quit(); return null }
  initializeDataFolder(chosen)
  saveSettings(userData, { ...settings, dataDir: chosen })
  return chosen
}

async function start() {
  const dataDir = await resolveDataDir()
  if (!dataDir) return
  createSplash()
  try {
    const url = await bootServer(dataDir)
    mainWindow = createMainWindow(url)
  } catch (e) {
    showErrorBox('Simply Suite failed to start', String((e && e.message) || e))
    app.quit()
    return
  } finally {
    closeSplash()
  }
  buildMenu({ onChangeDataFolder: () => {} }) // completed in Task 13
}

async function gracefulQuit() {
  if (isQuitting) return
  isQuitting = true
  await stopServer(serverChild)
  serverChild = null
  app.quit()
}

if (!app.requestSingleInstanceLock()) {
  app.quit()
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore()
      mainWindow.focus()
    }
  })
  app.whenReady().then(start)
}

app.on('window-all-closed', gracefulQuit)
app.on('before-quit', (e) => {
  if (isQuitting || !serverChild) return
  e.preventDefault()
  gracefulQuit()
})
