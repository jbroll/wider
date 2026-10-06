import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawn, spawnSync, execFileSync } from 'node:child_process'
import { once } from 'node:events'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import net from 'node:net'
import os from 'node:os'
import fs from 'node:fs'
import http from 'node:http'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.join(HERE, '..')

function freePort() {
  return new Promise((resolve, reject) => {
    const probe = net.createServer()
    probe.listen(0, '127.0.0.1', () => {
      const { port } = probe.address()
      probe.close(() => resolve(port))
    })
    probe.on('error', reject)
  })
}

async function start(extraEnv = {}) {
  execFileSync('node', [path.join(ROOT, 'build.js')], { stdio: 'ignore' })
  // A fixed test port, not the app default, so these tests don't collide with a
  // mapper instance the developer already has running.
  const env = { ...process.env, MAPPER_PORT: String(await freePort()), ...extraEnv }
  const child = spawn('node', [path.join(ROOT, 'serve.js')], { stdio: ['ignore', 'pipe', 'inherit'], env })
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

async function fakeOrs() {
  const seen = []
  const server = http.createServer(async (req, res) => {
    let body = ''
    for await (const chunk of req) body += chunk
    seen.push({ method: req.method, url: req.url, type: req.headers['content-type'], body })
    res.writeHead(201, { 'Content-Type': 'application/geo+json', 'X-Ors': 'yes' })
    res.end('{"type":"FeatureCollection","features":[]}')
  })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  return { seen, url: `http://127.0.0.1:${server.address().port}/ors`, close: () => new Promise((r) => server.close(r)) }
}

test('the server proxies /ors/ to the routing service with method, query and body', async () => {
  const ors = await fakeOrs()
  const { child, url } = await start({ MAPPER_ORS_URL: ors.url })
  try {
    const res = await fetch(url + '/ors/v2/directions/foot-walking/geojson?token=abc', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{"coordinates":[[1,2],[3,4]]}',
    })
    assert.equal(res.status, 201)
    assert.equal(res.headers.get('content-type'), 'application/geo+json')
    assert.equal(res.headers.get('x-ors'), 'yes')
    assert.equal(await res.text(), '{"type":"FeatureCollection","features":[]}')
    assert.deepEqual(ors.seen, [{
      method: 'POST',
      url: '/ors/v2/directions/foot-walking/geojson?token=abc',
      type: 'application/json',
      body: '{"coordinates":[[1,2],[3,4]]}',
    }])
  } finally {
    child.kill()
    await once(child, 'exit')
    await ors.close()
  }
})

test('the server answers 502 when the routing service is down', async () => {
  const { child, url } = await start({ MAPPER_ORS_URL: `http://127.0.0.1:${await freePort()}/ors` })
  try {
    const res = await fetch(url + '/ors/v2/directions/foot-walking/geojson', { method: 'POST', body: '{}' })
    assert.equal(res.status, 502)
  } finally {
    child.kill()
    await once(child, 'exit')
  }
})

test('the server proxies only paths under /ors/', async () => {
  const ors = await fakeOrs()
  const { child, url } = await start({ MAPPER_ORS_URL: ors.url })
  try {
    assert.equal((await fetch(url + '/ors')).status, 404)
    assert.equal((await fetch(url + '/orsx/v2')).status, 404)
    assert.deepEqual(ors.seen, [])
  } finally {
    child.kill()
    await once(child, 'exit')
    await ors.close()
  }
})

async function fakeGeocoder() {
  const seen = []
  const server = http.createServer((req, res) => {
    seen.push({ method: req.method, url: req.url })
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end('{"type":"FeatureCollection","features":[]}')
  })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  return { seen, url: `http://127.0.0.1:${server.address().port}`, close: () => new Promise((r) => server.close(r)) }
}

test('the server proxies /geocode/ to the geocoder with path and query', async () => {
  const geo = await fakeGeocoder()
  const { child, url } = await start({ MAPPER_GEOCODE_URL: geo.url })
  try {
    const res = await fetch(url + '/geocode/v1/autocomplete?text=120+state&token=abc')
    assert.equal(res.status, 200)
    assert.equal(await res.text(), '{"type":"FeatureCollection","features":[]}')
    assert.deepEqual(geo.seen, [{ method: 'GET', url: '/v1/autocomplete?text=120+state&token=abc' }])
  } finally {
    child.kill()
    await once(child, 'exit')
    await geo.close()
  }
})

test('the server answers 502 when the geocoder is down', async () => {
  const { child, url } = await start({ MAPPER_GEOCODE_URL: `http://127.0.0.1:${await freePort()}` })
  try {
    const res = await fetch(url + '/geocode/v1/autocomplete?text=abc')
    assert.equal(res.status, 502)
  } finally {
    child.kill()
    await once(child, 'exit')
  }
})

test('the server proxies only paths under /geocode/ to the geocoder', async () => {
  const geo = await fakeGeocoder()
  const { child, url } = await start({ MAPPER_GEOCODE_URL: geo.url })
  try {
    assert.equal((await fetch(url + '/geocode')).status, 404)
    assert.equal((await fetch(url + '/geocodex/v1')).status, 404)
    assert.deepEqual(geo.seen, [])
  } finally {
    child.kill()
    await once(child, 'exit')
    await geo.close()
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

test('the server exits nonzero with a message when the port is taken', async () => {
  const port = await freePort()
  const holder = net.createServer()
  holder.on('error', (err) => assert.fail(`holder server: ${err}`))
  await new Promise((resolve) => holder.listen(port, '127.0.0.1', resolve))
  try {
    execFileSync('node', [path.join(ROOT, 'build.js')], { stdio: 'ignore' })
    const child = spawn('node', [path.join(ROOT, 'serve.js')],
      { stdio: ['ignore', 'ignore', 'pipe'], env: { ...process.env, MAPPER_PORT: String(port) } })
    let err = ''
    child.stderr.on('data', (chunk) => { err += chunk })
    const [code] = await once(child, 'exit')
    assert.notEqual(code, 0)
    assert.match(err, /already in use/)
  } finally {
    await new Promise((resolve) => holder.close(resolve))
  }
})

test('the launcher exits nonzero and never opens Chromium when its port is busy', async () => {
  const port = await freePort()
  const holder = net.createServer()
  holder.on('error', (err) => assert.fail(`holder server: ${err}`))
  await new Promise((resolve) => holder.listen(port, '127.0.0.1', resolve))

  // A fake chromium ahead of the real one on PATH: if the launcher ever runs
  // it, the sentinel file proves the window would have opened.
  const fakeBinDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mapper-fake-bin-'))
  const sentinel = path.join(fakeBinDir, 'chromium-ran')
  fs.writeFileSync(path.join(fakeBinDir, 'chromium'), `#!/bin/sh\ntouch "${sentinel}"\n`, { mode: 0o755 })

  try {
    execFileSync('node', [path.join(ROOT, 'build.js')], { stdio: 'ignore' })
    const result = spawnSync('sh', [path.join(ROOT, 'mapper')], {
      encoding: 'utf8',
      env: { ...process.env, PATH: `${fakeBinDir}:${process.env.PATH}`, MAPPER_PORT: String(port) },
    })
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /already in use/)
    assert.match(result.stderr, /MAPPER_PORT/)
    assert.equal(fs.existsSync(sentinel), false)
  } finally {
    await new Promise((resolve) => holder.close(resolve))
    fs.rmSync(fakeBinDir, { recursive: true, force: true })
  }
})

async function waitForPortFree(port, timeoutMs = 2000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const free = await new Promise((resolve) => {
      const socket = net.connect({ host: '127.0.0.1', port, timeout: 200 })
      socket.once('connect', () => { socket.destroy(); resolve(false) })
      socket.once('timeout', () => { socket.destroy(); resolve(true) })
      socket.once('error', () => resolve(true))
    })
    if (free) return true
    await new Promise((resolve) => setTimeout(resolve, 100))
  }
  return false
}

test('the launcher exits nonzero and never opens Chromium when node is nowhere to be found', () => {
  const fakeBinDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mapper-fake-bin-'))
  const sentinel = path.join(fakeBinDir, 'chromium-ran')
  fs.writeFileSync(path.join(fakeBinDir, 'chromium'), `#!/bin/sh\ntouch "${sentinel}"\n`, { mode: 0o755 })
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'mapper-fake-home-'))

  try {
    const result = spawnSync('sh', [path.join(ROOT, 'mapper')], {
      encoding: 'utf8',
      env: {
        PATH: `${fakeBinDir}:/usr/bin:/bin`,
        HOME: home,
        NVM_DIR: path.join(home, 'no-such-nvm'),
      },
    })
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /node/)
    assert.equal(fs.existsSync(sentinel), false)
  } finally {
    fs.rmSync(fakeBinDir, { recursive: true, force: true })
    fs.rmSync(home, { recursive: true, force: true })
  }
})

test('the launcher resolves node from an nvm install when node is not on PATH', async () => {
  const port = await freePort()

  const fakeBinDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mapper-fake-bin-'))
  const sentinel = path.join(fakeBinDir, 'chromium-ran')
  fs.writeFileSync(path.join(fakeBinDir, 'chromium'), `#!/bin/sh\ntouch "${sentinel}"\nexit 0\n`, { mode: 0o755 })

  const nvmDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mapper-fake-nvm-'))
  const nodeBinDir = path.join(nvmDir, 'versions', 'node', 'v22.0.0', 'bin')
  fs.mkdirSync(nodeBinDir, { recursive: true })
  fs.writeFileSync(path.join(nodeBinDir, 'node'), `#!/bin/sh\nexec "${process.execPath}" "$@"\n`, { mode: 0o755 })

  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'mapper-fake-home-'))

  try {
    execFileSync('node', [path.join(ROOT, 'build.js')], { stdio: 'ignore' })
    const result = spawnSync('sh', [path.join(ROOT, 'mapper')], {
      encoding: 'utf8',
      env: {
        PATH: `${fakeBinDir}:/usr/bin:/bin`,
        HOME: home,
        NVM_DIR: nvmDir,
        MAPPER_PORT: String(port),
      },
    })
    assert.equal(result.status, 0, result.stderr)
    assert.equal(fs.existsSync(sentinel), true)
    assert.equal(await waitForPortFree(port), true)
  } finally {
    fs.rmSync(fakeBinDir, { recursive: true, force: true })
    fs.rmSync(nvmDir, { recursive: true, force: true })
    fs.rmSync(home, { recursive: true, force: true })
  }
})

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
