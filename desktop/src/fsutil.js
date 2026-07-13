const fs = require('fs')
const path = require('path')
const crypto = require('crypto')

// Relative paths of every file under `root` (files only), sorted.
function listFilesRecursive(root) {
  const out = []
  const walk = (dir) => {
    const entries = fs.readdirSync(dir, { withFileTypes: true })
    for (const e of entries) {
      const abs = path.join(dir, e.name)
      if (e.isDirectory()) walk(abs)
      else if (e.isFile()) out.push(path.relative(root, abs))
    }
  }
  if (fs.existsSync(root)) walk(root)
  return out.sort()
}

// SHA-256 hex of a file's contents.
function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')
}

// Recursively copy the tree at `src` into `dest` (created if absent).
function copyTree(src, dest) {
  fs.mkdirSync(dest, { recursive: true })
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const from = path.join(src, e.name)
    const to = path.join(dest, e.name)
    if (e.isDirectory()) copyTree(from, to)
    else if (e.isFile()) fs.copyFileSync(from, to)
  }
}

// Remove a directory tree if it exists.
function removeTree(dir) {
  fs.rmSync(dir, { recursive: true, force: true })
}

// True if `dir` is writable, proven by creating then deleting a temp file.
function testWritable(dir) {
  try {
    fs.mkdirSync(dir, { recursive: true })
    const probe = path.join(dir, `.write-test-${process.pid}-${Date.now()}`)
    fs.writeFileSync(probe, 'ok')
    fs.unlinkSync(probe)
    return true
  } catch {
    return false
  }
}

module.exports = { listFilesRecursive, sha256, copyTree, removeTree, testWritable }
