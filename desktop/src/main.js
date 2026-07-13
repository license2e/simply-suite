const { app, BrowserWindow } = require('electron')

app.whenReady().then(() => {
  const win = new BrowserWindow({ width: 900, height: 600 })
  win.loadURL('data:text/html,<h1>Simply Suite desktop shell</h1>')
})

app.on('window-all-closed', () => app.quit())
