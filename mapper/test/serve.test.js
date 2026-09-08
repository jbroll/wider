import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawn, execFileSync } from 'node:child_process'
import { once } from 'node:events'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.join(HERE, '..')

async function start() {
  execFileSync('node', [path.join(ROOT, 'build.js')], { stdio: 'ignore' })
  const child = spawn('node', [path.join(ROOT, 'serve.js')], { stdio: ['ignore', 'pipe', 'inherit'] })
  let out = ''
  for await (const chunk of child.stdout) {
    out += chunk
    if (out.includes('\n')) break
  }
  const port = Number(out.trim())
  assert.ok(Number.isInteger(port) && port > 0, `expected a port, got ${JSON.stringify(out)}`)
  return { child, url: `http://127.0.0.1:${port}` }
}

test('the server prints its port and serves the built page', async () => {
  const { child, url } = await start()
  try {
    const res = await fetch(url + '/')
    assert.equal(res.status, 200)
    assert.match(res.headers.get('content-type'), /text\/html/)
    const body = await res.text()
    assert.match(body, /^<!doctype html>/i)
    assert.match(body, /<div id="map">/)
  } finally {
    child.kill()
    await once(child, 'exit')
  }
})

test('the server answers 404 off the root path', async () => {
  const { child, url } = await start()
  try {
    assert.equal((await fetch(url + '/nope')).status, 404)
  } finally {
    child.kill()
    await once(child, 'exit')
  }
})

test('the server binds loopback only', async () => {
  const { child, url } = await start()
  try {
    assert.match(url, /^http:\/\/127\.0\.0\.1:/)
  } finally {
    child.kill()
    await once(child, 'exit')
  }
})
