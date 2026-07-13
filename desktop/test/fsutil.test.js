const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { listFilesRecursive, sha256, copyTree, removeTree, testWritable } = require('../src/fsutil')

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'ss-fsutil-'))

test('listFilesRecursive returns sorted relative file paths', () => {
  const d = tmp()
  fs.mkdirSync(path.join(d, 'a'))
  fs.writeFileSync(path.join(d, 'a', 'x.json'), '1')
  fs.writeFileSync(path.join(d, 'top.txt'), '2')
  assert.deepStrictEqual(listFilesRecursive(d), [path.join('a', 'x.json'), 'top.txt'])
  removeTree(d)
})

test('copyTree reproduces files with identical checksums', () => {
  const src = tmp(); const dest = path.join(tmp(), 'out')
  fs.writeFileSync(path.join(src, 'f.txt'), 'hello')
  copyTree(src, dest)
  assert.strictEqual(sha256(path.join(dest, 'f.txt')), sha256(path.join(src, 'f.txt')))
  removeTree(src); removeTree(dest)
})

test('testWritable: true for a fresh dir, false for an unwritable path', () => {
  const d = tmp()
  assert.strictEqual(testWritable(d), true)
  assert.strictEqual(testWritable('/proc/nonexistent/cannot'), false)
  removeTree(d)
})
