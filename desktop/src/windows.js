const { BrowserWindow } = require('electron')
const path = require('path')

let splash = null

function createSplash() {
  splash = new BrowserWindow({
    width: 420, height: 260, frame: false, resizable: false, show: true,
    webPreferences: { contextIsolation: true, nodeIntegration: false }
  })
  splash.loadFile(path.join(__dirname, 'splash.html'))
  return splash
}

function closeSplash() {
  if (splash && !splash.isDestroyed()) splash.close()
  splash = null
}

function createMainWindow(url) {
  const win = new BrowserWindow({
    width: 1280, height: 860, show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  })
  win.once('ready-to-show', () => win.show())
  win.loadURL(url)
  return win
}

module.exports = { createSplash, closeSplash, createMainWindow }
