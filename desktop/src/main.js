const { app } = require('electron')
const path = require('path')
const fs = require('fs')
const { loadSettings, saveSettings, getOrCreateSessionSecret } = require('./settings')
const { defaultDataDir, initializeDataFolder, isDataFolder, resolveTarget } = require('./data-dir')
const { pickFreePort, rubyLauncher, startServer, waitForHealth, stopServer, rubyBinName } = require('./server')
const { createSplash, closeSplash, createMainWindow } = require('./windows')
const { runOnboarding, chooseFolder, confirmAdopt, showErrorBox } = require('./dialogs')
const { migrate } = require('./migration')
const { testWritable } = require('./fsutil')
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
      cmd: path.join(process.resourcesPath, 'ruby', 'bin', rubyBinName()),
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
  buildMenu({ onChangeDataFolder: changeDataFolder })
}

async function gracefulQuit() {
  if (isQuitting) return
  isQuitting = true
  await stopServer(serverChild)
  serverChild = null
  app.quit()
}

// Change the data folder from the menu: pick → write-test → conflict check →
// stop server → migrate (or adopt) → save → restart. Fail-safe: on migrate
// failure the old data is untouched and the app restarts on it.
async function changeDataFolder() {
  const picked = await chooseFolder('Choose a new folder for Simply Suite data')
  if (!picked) return
  const newDir = resolveTarget(picked)
  if (path.resolve(newDir) === path.resolve(currentDataDir)) return

  if (!testWritable(newDir)) {
    showErrorBox('Cannot use that folder', `Simply Suite can't write to:\n${newDir}`)
    return
  }

  // Never migrate INTO a non-empty folder that isn't ours: migrate() would copy
  // on top of the existing files and, on a verify mismatch, remove the whole
  // folder — destroying unrelated data. Adopting an existing SS folder (marker
  // present) is handled below; an empty or not-yet-created target is a fresh migrate.
  if (!isDataFolder(newDir) && fs.existsSync(newDir) && fs.readdirSync(newDir).length > 0) {
    showErrorBox('Folder not empty', `That folder already contains other files:\n${newDir}\n\nChoose an empty folder, or one that already holds Simply Suite data.`)
    return
  }

  const adoptExisting = isDataFolder(newDir)
  if (adoptExisting && !(await confirmAdopt(newDir))) return

  const oldDir = currentDataDir
  createSplash()
  if (mainWindow) mainWindow.hide()
  await stopServer(serverChild)
  serverChild = null

  let dataDir = oldDir
  try {
    if (adoptExisting) {
      dataDir = newDir                 // switch only; leave old data in place
    } else {
      initializeDataFolder(newDir)
      migrate(oldDir, newDir)          // copy → verify → delete old
      dataDir = newDir
    }
    saveSettings(app.getPath('userData'), { ...loadSettings(app.getPath('userData')), dataDir })
  } catch (e) {
    dataDir = oldDir                    // migrate failed before deleting → old intact
    showErrorBox('Data move failed', `${(e && e.message) || e}\n\nYour data was left in its original location.`)
  }

  try {
    const url = await bootServer(dataDir)
    if (mainWindow) mainWindow.loadURL(url)
  } catch (e) {
    showErrorBox('Simply Suite failed to restart', String((e && e.message) || e))
    app.quit()
    return
  } finally {
    if (mainWindow) mainWindow.show()
    closeSplash()
  }
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
