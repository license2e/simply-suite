const { dialog } = require('electron')
const { resolveTarget } = require('./data-dir')

// First-run onboarding. Returns the resolved data-folder path, or null to quit.
async function runOnboarding(defaultDir) {
  const { response } = await dialog.showMessageBox({
    type: 'question',
    buttons: ['Use default location', 'Choose a folder…', 'Quit'],
    defaultId: 0, cancelId: 2,
    title: 'Simply Suite',
    message: 'Where should Simply Suite store your data?',
    detail: `Default location:\n${defaultDir}`
  })
  if (response === 0) return defaultDir
  if (response === 2) return null
  const picked = await chooseFolder('Choose a folder for Simply Suite data')
  return picked ? resolveTarget(picked) : null
}

// Native folder picker. Returns the selected path or null.
async function chooseFolder(title) {
  const { canceled, filePaths } = await dialog.showOpenDialog({
    title: title || 'Choose a folder',
    properties: ['openDirectory', 'createDirectory']
  })
  return canceled || !filePaths.length ? null : filePaths[0]
}

// Ask whether to adopt existing data at newDir. Returns true to adopt.
async function confirmAdopt(newDir) {
  const { response } = await dialog.showMessageBox({
    type: 'warning',
    buttons: ['Adopt existing data', 'Cancel'],
    defaultId: 0, cancelId: 1,
    title: 'Existing data found',
    message: 'That folder already contains Simply Suite data.',
    detail: `Switch to the data already in:\n${newDir}\n\nYour current data is left where it is — not copied, not deleted.`
  })
  return response === 0
}

function showErrorBox(title, message) {
  dialog.showErrorBox(title, message)
}

module.exports = { runOnboarding, chooseFolder, confirmAdopt, showErrorBox }
