const { test } = require('node:test')
const assert = require('node:assert')
const { rubyBinName } = require('../src/server')

test('rubyBinName returns ruby.exe on win32', () => {
  assert.strictEqual(rubyBinName('win32'), 'ruby.exe')
})

test('rubyBinName returns ruby on macOS and Linux', () => {
  assert.strictEqual(rubyBinName('darwin'), 'ruby')
  assert.strictEqual(rubyBinName('linux'), 'ruby')
})

test('rubyBinName defaults to the current platform', () => {
  const expected = process.platform === 'win32' ? 'ruby.exe' : 'ruby'
  assert.strictEqual(rubyBinName(), expected)
})
