const fs = require('fs')
const path = require('path')

const MARKER = '.simply-suite.json'
const DATA_SUBFOLDER = 'Simply Suite'

// Default data folder: a dedicated subfolder inside Electron's userData dir.
function defaultDataDir(userDataDir) {
  return path.join(userDataDir, 'data')
}

// True if `dir` already carries the Simply Suite marker.
function isDataFolder(dir) {
  return fs.existsSync(path.join(dir, MARKER))
}

// Decide the actual data folder for a folder the user picked: if they pointed
// straight at an existing SS folder, use it in place; otherwise nest a
// dedicated "Simply Suite" subfolder so we never own their whole parent folder.
function resolveTarget(pickedDir) {
  return isDataFolder(pickedDir) ? pickedDir : path.join(pickedDir, DATA_SUBFOLDER)
}

// Ensure the folder exists and carries the marker. Returns `dir`.
function initializeDataFolder(dir) {
  fs.mkdirSync(dir, { recursive: true })
  const marker = path.join(dir, MARKER)
  if (!fs.existsSync(marker)) {
    fs.writeFileSync(marker, JSON.stringify({ app: 'simply-suite', schema: 1 }, null, 2))
  }
  return dir
}

module.exports = { MARKER, DATA_SUBFOLDER, defaultDataDir, isDataFolder, resolveTarget, initializeDataFolder }
