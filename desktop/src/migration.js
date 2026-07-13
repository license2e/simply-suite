const fs = require('fs')
const path = require('path')
const { listFilesRecursive, sha256, copyTree, removeTree } = require('./fsutil')

// Verify `dest` is a byte-for-byte copy of `src`: same relative file set, each
// with matching size and SHA-256. Returns { ok, reason? }.
function verifyCopy(src, dest) {
  const a = listFilesRecursive(src)
  const b = listFilesRecursive(dest)
  if (a.length !== b.length || a.some((f, i) => f !== b[i])) {
    return { ok: false, reason: 'file set differs' }
  }
  for (const rel of a) {
    const fa = path.join(src, rel)
    const fb = path.join(dest, rel)
    if (fs.statSync(fa).size !== fs.statSync(fb).size) return { ok: false, reason: `size differs: ${rel}` }
    if (sha256(fa) !== sha256(fb)) return { ok: false, reason: `checksum differs: ${rel}` }
  }
  return { ok: true }
}

// Move data from oldDir to newDir with verification. Copies, verifies
// byte-for-byte, and ONLY THEN deletes oldDir. On any failure the partial
// newDir is removed and oldDir is left intact; the error is re-thrown so the
// caller can keep running on oldDir. Precondition: newDir is empty/new
// (adopt/conflict cases are resolved by the caller).
function migrate(oldDir, newDir) {
  try {
    copyTree(oldDir, newDir)
  } catch (e) {
    removeTree(newDir)
    throw new Error(`copy failed: ${e.message}`)
  }
  const result = verifyCopy(oldDir, newDir)
  if (!result.ok) {
    removeTree(newDir)
    throw new Error(`verification failed: ${result.reason}`)
  }
  removeTree(oldDir)
}

module.exports = { verifyCopy, migrate }
