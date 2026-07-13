const fs = require('fs')
const path = require('path')
const crypto = require('crypto')

function settingsPath(userDataDir) {
  return path.join(userDataDir, 'config.json')
}

// Read settings; returns {} if the file is missing, unreadable, or corrupt.
function loadSettings(userDataDir) {
  try {
    return JSON.parse(fs.readFileSync(settingsPath(userDataDir), 'utf8'))
  } catch {
    return {}
  }
}

// Persist settings atomically (temp file + rename).
function saveSettings(userDataDir, settings) {
  fs.mkdirSync(userDataDir, { recursive: true })
  const file = settingsPath(userDataDir)
  const tmp = `${file}.tmp-${process.pid}`
  fs.writeFileSync(tmp, JSON.stringify(settings, null, 2))
  fs.renameSync(tmp, file)
}

// Return the persisted session secret, generating and saving one on first use.
function getOrCreateSessionSecret(userDataDir) {
  const s = loadSettings(userDataDir)
  if (s.sessionSecret) return s.sessionSecret
  s.sessionSecret = crypto.randomBytes(64).toString('hex')
  saveSettings(userDataDir, s)
  return s.sessionSecret
}

module.exports = { settingsPath, loadSettings, saveSettings, getOrCreateSessionSecret }
