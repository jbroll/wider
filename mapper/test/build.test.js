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
})

// The style is the only origin the page fetches. Everything else the bundle
// names is a link target in MapLibre's attribution and logo controls.
const REACHABLE = new Set(['https://tiles.openfreemap.org'])
const LINKED = new Set(['https://maplibre.org'])
// An XML namespace, and an issue-tracker URL inside a console warning string.
// Neither is fetched or a link the page renders.
const NOT_A_REQUEST = new Set(['http://www.w3.org', 'https://github.com'])

test('the bundle names no origin beyond the style and its attribution links', async () => {
  const html = await buildHtml()
  for (const match of html.matchAll(/https?:\/\/[^"'\s)\\]+/g)) {
    if (match[0].includes('${')) continue
    let origin
    try { origin = new URL(match[0]).origin } catch { origin = match[0] }
    if (NOT_A_REQUEST.has(origin)) continue
    assert.ok(REACHABLE.has(origin) || LINKED.has(origin),
      `unexpected origin in the built page: ${origin}`)
  }
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
