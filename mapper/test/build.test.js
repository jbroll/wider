import { test } from 'node:test'
import assert from 'node:assert/strict'

import { buildHtml } from '../build.js'

test('the build inlines everything into one document', async () => {
  const html = await buildHtml()
  assert.match(html, /^<!doctype html>/i)
  assert.match(html, /<style>/)
  assert.match(html, /<script>/)
  assert.doesNotMatch(html, /<script[^>]+\ssrc=/)
  assert.doesNotMatch(html, /<link[^>]+rel=["']?stylesheet/)
  assert.doesNotMatch(html, /\s(?:src|href)\s*=\s*["']https?:\/\//i)
})

test('the slots are substituted', async () => {
  const html = await buildHtml()
  assert.doesNotMatch(html, /\/\*CSS\*\//)
  assert.doesNotMatch(html, /\/\*JS\*\//)
})

test('the mount points survive the build', async () => {
  const html = await buildHtml()
  assert.match(html, /<div id="map">/)
  assert.match(html, /<div id="panel">/)
})
