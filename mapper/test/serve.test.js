import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawn, execFileSync } from 'node:child_process'
import { once } from 'node:events'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import net from 'node:net'
import os from 'node:os'

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

function nonInternalIPv4() {
  const nets = os.networkInterfaces()
  for (const addrs of Object.values(nets)) {
    for (const addr of addrs ?? []) {
      if (addr.family === 'IPv4' && !addr.internal) return addr.address
    }
  }
  return null
}

test('the server binds loopback only', async (t) => {
  const host = nonInternalIPv4()
  if (!host) {
    t.skip('no non-loopback interface to probe')
    return
  }
  const { child, url } = await start()
  try {
    const port = Number(new URL(url).port)
    await assert.rejects(() => new Promise((resolve, reject) => {
      const socket = net.connect({ host, port, timeout: 2000 })
      socket.once('connect', () => { socket.destroy(); resolve() })
      socket.once('timeout', () => { socket.destroy(); reject(new Error('timed out')) })
      socket.once('error', (err) => { socket.destroy(); reject(err) })
    }))
  } finally {
    child.kill()
    await once(child, 'exit')
  }
})
